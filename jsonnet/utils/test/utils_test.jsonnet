#!/usr/bin/env jsonnet -J ./jsonnetunit

local utils = (import '../utils.libsonnet') {
  log_level:: self.TRACE,
};
local test = import 'jsonnetunit/test.libsonnet';

test.suite({
  'test log_level set': {
    actual: utils.log_level,
    expect: utils.TRACE,
  },

  'test safe_get basic': {
    actual: utils.safe_get({ a: { b: { c: 'yay' } } }, ['a', 'b', 'c'], 'boo'),
    expect: 'yay',
  },

  'test safe_get defaults': {
    actual: [
      utils.safe_get({ a: { b: { c: 'yay' } } }, ['a', 'b', 'nope'], 'default'),
      utils.safe_get({ a: { b: { c: 'yay' } } }, ['never'], 'default'),
    ],
    expect: ['default', 'default'],
  },

  'test safe_get edge cases': {
    actual: [
      utils.safe_get({ a: { b: { c: 'yay' } } }, [], 'default'),
      utils.safe_get({}, ['hello', 'world'], 'default'),
      utils.safe_get({ nothing: null }, ['nothing'], 'default'),
    ],
    expect: ['default', 'default', null],
  },

  'test contains function': {
    actual: [
      // true
      utils.contains(['alpha', 'beta', 'delta'], 'delta'),
      utils.contains({ hello: 'world', goodbye: 'world' }, 'hello'),
      utils.contains('hello world', 'world'),
      // false
      utils.contains(['alpha', 'beta', 'delta'], 'gamma'),
      utils.contains({ hello: 'world', goodbye: 'world' }, 'nothing'),
      utils.contains({ hello: 'world', goodbye: 'world' }, null),
      utils.contains('hello world', 'never'),
    ],
    expect: [
      true,
      true,
      true,
      false,
      false,
      false,
      false,
    ],
  },
})
