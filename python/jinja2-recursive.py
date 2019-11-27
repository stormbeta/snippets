#!/usr/bin/env python3

from jinja2 import Template
from jinja2.exceptions import UndefinedError

config = {}

def render_rec(obj, depth=0, rec=None, cfg=None):
    """
    Assumes that template input is always well-formed JSON, and template values only ever live in leaves
    If one or more template references can't be resolved, or do not resolve to a concrete value, the full object
    is re-templated by combining the config with the previous result as input
    I.e. allows this to work:
    {
        "value1": "{{ value2 }} one",
        "value2": "{{ original }} two",
        "original": "hello world"
    }
    """
    if rec is None and depth == 0:
        rec = []
    if cfg is None:
        # Enable recursive render on config itself as well
        cfg = render_rec(config, depth, rec, self.config)
    if isinstance(obj, dict):
        result = {k: render_rec(v, depth + 1, rec, cfg) for k, v in obj.items()}
    elif isinstance(obj, list):
        result = [render_rec(v, depth + 1, rec, cfg) for v in obj]
    elif isinstance(obj, str):
        try:
            r = Template(obj).render(cfg)
            # Check that template didn't return blank value AND that template isn't nested
            if (len(obj) > 0 and len(r) == 0) or Template(r).render(cfg) != r:
                rec.append(obj)
                return obj
            else:
                return r
        except UndefinedError as e:
            rec.append(obj)
            return obj
    else:
        return obj

    if depth != 0 or (depth == 0 and len(rec) == 0):
        return result
    else:
        rec = []
        cfg = {**cfg, **result}
        return render_rec(result, depth, rec, cfg)
