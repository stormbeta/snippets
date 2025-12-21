import multiprocessing
import threading
from functools import wraps
from queue import Queue, Empty
from typing import Callable, List, TypeVar, Iterable, Union, Optional

A = TypeVar('A')
B = TypeVar('B')

# Workaround for passing exceptions in threads back to caller
class ExceptableThread(threading.Thread):
    exception: Optional[Exception]

    def __init__(self, group=None, target=None, name=None, args=(), kwargs=None, *, daemon=None):
        super().__init__(group=group, target=target, name=name, args=args, kwargs=kwargs, daemon=daemon)
        self.exception = None

    def run(self):
        try:
            super().run()
        except Exception as err:
            self.exception = err

    def join(self, timeout=None):
        super().join(timeout=timeout)


# TODO: Possible to make return value a blocking iterable too?
def mutable_multimap(lst: Iterable[A],
                     func: Callable[[Queue, A], B],
                     trim: bool = True,
                     thread_count: int = multiprocessing.cpu_count()
                     ) -> List[B]:
    """
    Multithreaded collect helper based on a queue
    Allows adding additional items to be processed on the fly, e.g. for recursive crawls of tree-like or paginated data
    @param lst:     list of items to collect over
    @param func:    mapping function (allowed to add items to queue)
    @param trim:    optional - whether to omit entries if func returns None
    @param thread_count: optional - threads (defaults to cpu count)
    @return:        output list
    """
    queue = Queue()
    output: list = []
    error = threading.Event()

    def worker() -> None:
        while not queue.empty():
            if error.is_set():
                queue.task_done()
                return
            try:
                result = func(queue, queue.get())
            except Exception as err:
                error.set()
                queue.task_done()
                raise err
            if not (trim and result is None):
                output.append(result)
            queue.task_done()

    threads: List[ExceptableThread] = []
    for item in lst:
        queue.put(item)
    for i in range(thread_count):
        thread = ExceptableThread(target=worker, daemon=True)
        threads.append(thread)
        thread.start()
    queue.join()
    for thread in threads:
        thread.join()
    for thread in threads:
        if thread.exception:
            raise thread.exception
    return list(output)


# invariant: len(List[A]) == len(List[B])
def multimap(lst: Iterable[A], func: Callable[[A],B], threads: int = multiprocessing.cpu_count()) -> List[B]:
    """
    Same as mutable_multimap, but enforced 1-to-1 mapping (output list same size as input)
    """
    @wraps(func)
    def wrapped_func(_: Queue, item: A) -> B:
        return func(item)
    return mutable_multimap(lst, wrapped_func, trim=False, thread_count=threads)


class AutoDict(dict):
    def __getitem__(self, item):
        try:
            return super().__getitem__(item)
        except KeyError:
            new = type(self)()
            super().__setitem__(item, new)
            return new

    def set(self, keys: Union[str, list], value):
        if isinstance(keys, str):
            return super().__setitem__(keys, value)
        current = self
        while len(keys) > 1:
            head = keys.pop(0)
            current = current[head]
        current[keys.pop()] = value
        return current

    def get(self, keys: Union[str, list]):
        if isinstance(keys, str):
            return super().__getitem__(keys)
        current = self
        while len(keys) > 1:
            head = keys.pop(0)
            current = current[head]
        return current[keys.pop()]
