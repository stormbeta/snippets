import inspect
import sys
import time
from functools import wraps
from typing import Union, Callable, Any, TypeVar, Tuple, Type

F = TypeVar('F', bound=Callable[..., Any])


def dryrun_stub(dry_run: Union[bool, Callable[[], bool]],
                handler: Callable[[str], Any] = lambda stub: print(stub, file=sys.stderr)) -> Callable[[F], F]:
    """
    Decorator to conditionally log call instead of execute it based on dry_run bool/call
    :param dry_run: boolean or callable that returns boolean, indicates whether or not this is a dry run
    :param handler: callable accepting log string as parameter, defaults to print()
    """
    def decorator(func: F) -> F:
        @wraps(func)
        def wrapper(*args, **kwargs):
            if isinstance(dry_run, bool):
                is_dry = dry_run
            else:
                is_dry = dry_run()
            if is_dry:
                argdict: dict = inspect.signature(func).bind(*args, **kwargs).arguments
                argstr = ", ".join([f"{k}={v}" for k, v in argdict.items() if k != 'self'])
                handler(f"DRY_RUN:\n{func.__name__}({argstr})")
            else:
                return func(*args, **kwargs)
        return wrapper
    return decorator


def retry(times: int, interval: int = 5,
          exceptions: Tuple[Type[Exception]] = (Exception,),
          handler: Callable[[Exception, Any, Any], Any] = (lambda e, args, kwargs: None)
          )-> Callable[[F], F]:
    """
    Easy way to add automatic retry to methods
    @param times:      Number of attempts
    @param interval:   Waiting period between attempts in seconds
    @param exceptions: Which exceptions to retry on, defaulting to all of them
    @param handler:    Optional handler method, e.g. to log retry attempts.
                       Second and third arguments are args and kwargs of original call
    """
    def decorator(func: F) -> F:
        @wraps(func)
        def wrapped(*args, **kwargs):
            n: int = times
            while True:
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    n -= 1
                    if n == 0:
                        raise e
                    handler(e, args, kwargs)
                    time.sleep(interval)
        return wrapped
    return decorator
