#!/usr/bin/env python3

from injector import Injector, Key, inject, Binder, MappingKey

Greet = Key('greet')
Map = MappingKey('map')

class Foo:
    @inject
    def __init__(self, greet: Greet, map: Map):
        self.greet = greet
        self.map = map

def first(binder: Binder):
    binder.bind(Greet, 'hello')
    binder.bind(Map, {'a': "hi"})

def second(binder: Binder):
    binder.bind(Greet, 'world')
    binder.bind(Map, {'a': "bye", 'b': 'extra'})

def third(binder: Binder):
    binder.bind(Greet, 'Morning')
    binder.bind(Map, {'c': 'third'})

context = Injector([first, second, third])
a = context.get(Foo)

assert a.greet == "Morning"
assert a.map['c'] == 'third'
assert a.map['b'] == 'extra'
assert a.map['a'] == 'bye'

print(a.map)
