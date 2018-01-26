//Proof of concept for simple hierarchical context map for a DSL
//Based on code from my jenkins dsl project
//May need refactoring for real world use

interface ContextLookup {
    Optional lookup(String key)
}

interface ContextBind {
    void bind(String key, value)
}

/**
 * Hierarchical key-value scoping map, similar to hiera
 */

class ContextMap implements ContextLookup, ContextBind {
    final Map<String, ?> context

    private final Optional<ContextLookup> parent = Optional.empty()
    private List<String> path = []

    ContextMap() {
        context = [:]
    }

    ContextMap(Map<String, ?> existing) {
        context = [:]
        existing.each { k,v ->
          if(v instanceof Map) {
            context.put(k, new ContextMap(v))
          } else {
            context.put(k,v)
          }
        }
    }

    ContextMap(ContextLookup parent, context) {
        this.parent = Optional.of(parent)
        this.context = context
    }

    static ContextLookup mergeLookups(ContextLookup first, ContextLookup second) {
        return { Object ...args ->
            Optional box = (first.&lookup).call(*args)
            return box.present ? box : (second.&lookup).call(*args)
        } as ContextLookup
    }

    ContextLookup withFallback(ContextLookup fallback) {
        return mergeLookups(this, fallback)
    }

    void bindAppend(ContextLookup withScope, String key, value) {
        this.bind(key, (withScope.lookup(key).orElse([:])) + value)
    }

    void bindPrepend(ContextLookup withScope, String key, value) {
        this.bind(key, value + (withScope.lookup(key).orElse([:])))
    }

    //Check this context for value, then check parent context if possible
    //Assumes nobody is storing null values, so null is equivalent to missing key
    Optional lookup(String key) {
        def v = Optional.ofNullable(context.get(key))
        def result = v.isPresent() ? v : parent.flatMap { p ->
          def parentValue = p.lookup(key)
          // sub-contexts returned from a parent should be chained as child contexts
          // to prevent accidental modification of parent context values
          if(parentValue.isPresent() && parentValue.get() instanceof ContextMap) {
            context.put(key, parentValue.get().createChildContext())
            return Optional.of(context.get(key))
          } else {
            return parentValue
          }
        }
        return result.map { value ->
            //This is required to ensure binders can't accidentally modify higher scope defaults for map/list values
            //i.e. 'something.map.put(key,value)' is illegal, but 'something.map = something.map + [key: value]' is okay
            //Not needed for Strings, since those are already immutable by default in the JVM
            value instanceof Collection ? value.asImmutable() : value
        }
    }

    // Convenience method to unbox Optional if you don't care about the exception
    // or want to handle the exception yourself
    def lookupValue(String key) {
        return lookup(key).get()
    }

    void bind(String key, value) {
        if(value == null) {
            throw new RuntimeException("Attempted to set ${key} to null value, which is not allowed!")
        }
        if(value instanceof ContextMap) {
            value.path = this.path.clone() + ['key']
        }
        context.put(key, value)
    }

    // Creates child scope
    ContextMap createChildContext() {
        return new ContextMap(this, [:])
    }

    void call(Closure body) {
      new ProxyDelegate(this).with(body)
    }
}

class ProxyDelegate {
  private final ContextMap context

  ProxyDelegate(ContextMap context) {
    this.context = context
  }

  void propertyMissing(String name, value) {
      context.bind(name, value)
  }

  def propertyMissing(String name) {
    def value = context.lookupValue(name)
    if(value instanceof ContextMap) {
      return new ProxyDelegate(value)
    } else {
      return value
    }
  }

  ContextMap getContextMap() {
    return context
  }
}

def defaults = new ContextMap([
  section: [
    field1: 'value1',
    field2: 'value2',
  ],
])

def config = defaults.createChildContext()

config {
  section.field1 = 'hello world'
  println section.field1 // "hello world"
}

defaults {
  println section.field1 // "value1"
}
