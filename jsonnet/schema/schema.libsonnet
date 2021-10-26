#!/usr/bin/env jsonnet

/*
=== Schema Reference ===

Primitives, e.g. 'string', 'object', 'number', 'array', etc.
  These are matched directly using jsonnet's std.type(...)

Objects or arrays in the schema are used to recurse down and validate nested values

Function extensions
-------------------

Enum([VALUES...])
  Data must literally equal one of the provided values

Optional(SCHEMA)
  Will match data gainst provided schema if it exists
  If it doesn't exist, it will be ignored
  If used on a field value, the field will not be in the output

Array(SCHEMA)
  Will check that all values in the array match the schema
  (i.e. array must have homogenous type)

MapOf(SCHEMA)
  Will check that all fields in the object have values of the same provided type
  There's no schema for the keys since keys are always string in JSON

Either([SCHEMAS...])
  Will check that data matches at least one of the provided schemas

CustomValidator(FUNCTION(DATA)->[ERRORS...])
  Uses provided function to validate data directly.
  If error array is empty, data is valid

If you want to write your own function, it must look something like this:
function(...)
  function(validate, vdata) -> vdata
     // CAUTION: vdata.value is allowed to be null here, and you must handle that case!
     // 'validate' arg is the internal validator function with signature `validate(vdata, schema)`
     // NOTE: if you choose not to call the internal validator, you must ensure you return an intact vdata object yourself!

Example identity function:
```jsonnet
  example: function(schema)
    function(validate, vdata)
      validate(vdata, schema)
```

Example no-op function that returns input with no further validation
```jsonnet
  example: function(validate, vdata)
    vdata
```

You can also safely nest things however you want, e.g.:
```jsonnet
  example: v.Optional(
    v.Custom(function(array)
      if !(std.type(array) == 'array' && std.length(array) >= 3) then
        'ERROR: Expected array of length >= 3'
    )),
```

=== GLOSSARY ===

SCHEMA:
  has same structure as data, but indicates expected types/values

DATA:
  raw input data

VDATA:
  Wrapped input data with metadata fields
  MAYBE_VDATA => indicates the vdata object may have a missing 'value' field

VDATA structure = {
  schemaDescription: human-friendly name of current schema context / expected type

  value: Optional<DATA>,

  errors: ARRAY[{
    path: contextPath,
    error: message,
    ...
  }],

  context: ARRAY[{
    type: field|index,
    value: field name or index number
  }]

  optional: Optional<BOOLEAN>
}

VALIDATOR FUNCTIONS
Signature: function(vdata) -> vdata
Contract:
  * _MUST_ check if vdata.value field exists, if not return $.withMissingError
  * Recommended: Extend from passed vdata object - if you don't, withError/withMissingError will not work
  * Recommended: Inject { schemaDescription: ... } after vdata - if you don't, you won't get human-readable expected: ... in error output

CONTEXT:
  Array of type/value tuples used to construct a jq-like path for error reporting
*/

local
  contains = function(collection, ref)
    if std.type(collection) == 'object' then
      std.objectHas(collection, ref)
    else
      std.member(collection, ref),

  combine = function(items)
    std.foldl(
      function(sum, item) sum + item,
      items,
      []
    ),

  prettyPrintErrors = function(errors)
    std.join('\n\n', [
      local maxLength = function(a, b) std.max(a, std.length(b));
      local maxLabelLen = std.foldl(maxLength, std.objectFields(err), 0) + 1;
      std.join('\n', [
        local labelLen = std.length(label);
        std.asciiUpper(label) + ':'
        + std.repeat(' ', maxLabelLen - labelLen) + err[label]
        for label in std.objectFields(err)
      ])
      for err in errors
    ]) + '\n',


  // safe field reference with default if field not present
  maybeGet = function(object, field, default={})
    if std.objectHas(object, field)
    then object[field]
    else default
;


{
  // VDATA => boolean
  // TODO: Unused?
  isValid:: function(vdata)
    std.length(vdata.errors) > 0,

  // jq-style representation of current context in object
  // @context: [{type: field|index, value: ...}]
  contextPath:: function(context)
    if std.length(context) == 0 then
      '.'
    else
      std.foldl(
        function(path, contextEntry)
          path +
          if contextEntry.type == 'index' then
            '[%i]' % contextEntry.value
          else
            '.' + contextEntry.value,
        context,
        ''
      ),

  // Functions cannot be inspected or converted to strings
  // But we still want meaningful error output on function-based validation
  // so functions have the option of including a 'schemaDescription' into the vdata
  // result, which we obtain by making a dummy call on the extension function
  schemaToString:: function(schema)
    local traverse = function(_schema)
      local type = std.type(_schema);
      if type == 'function' then
        if std.length(_schema) != 1 then
          error 'validators must have one argument'
        else
          // TODO: This is a horrible hack
          //       But there might not be a better way, we need to be able to inspect
          //       schema top-down to report useful errors
          local inspect = _schema({ context: [] });
          if std.objectHas(inspect, 'schemaDescription') then
            inspect.schemaDescription
          else
            '<function>'
      else if type == 'object' then {
        [field]: traverse(_schema[field])
        for field in std.objectFields(_schema)
      }
      else if type == 'array' then [
        traverse(item)
        for item in _schema
      ]
      else _schema;
    std.toString(traverse(schema)),

  // Simple error injector, automatically includes expected and context fields
  // super<VDATA> -> string|{LABEL: string} -> VDATA
  withError:: function(message)
    {
      local context = super.context,
      local schemaDescription = super.schemaDescription,
      local optional = if 'optional' in self then self.optional else false,
      errors+: [
        {
          path: $.contextPath(context),
          expected: schemaDescription +
                    if optional then '?' else '',
        } +
        if std.type(message) == 'string' then
          { 'error': message }
        else
          message,
      ],
    },

  // Inject standard missing field error
  // All function validators should return this if VDATA.value is missing
  // super<VDATA> -> VDATA
  withMissingError:: $.withError('Required field does not exist!'),

  bind:: {
    // === Validator ===
    // schema:: (VDATA -> VDATA) -> schema -> (VDATA -> VDATA)
    schemaValidator:: function(validator, schema)
      function(vdata)
        $.validate(validator(vdata), schema),

    // schema:: schema -> VDATA -> VDATA
    schema:: function(schema, vdata)
      vdata + $.validate(vdata, schema),

    // === VDATA ===

    // DATA => VDATA
    // fieldName:: VDATA -> string -> VDATA
    fieldName:: function(vdata, field)
      (if field in vdata then { value: field } else {}) + {
        errors+: [],
        context: vdata.context + [{ type: 'field', value: field }],
      },

    // fieldValue:: VDATA -> string -> VDATA
    fieldValue: function(vdata, field)
      (if field in vdata.value then { value: vdata.value[field] } else {}) +
      {
        errors+: [],
        context: vdata.context + [{ type: 'field', value: field }],
      },

    // index:: VDATA -> integer -> VDATA
    index:: function(vdata, index) {
      value: vdata.value[index],
      errors+: [],
      context: vdata.context + [{ type: 'index', value: index }],
    },

    // For arrays and objects, we only need to keep value and error fields
    // * 'optional' is used in object bind to strip missing values
    // * 'schemaDescription' is only used for error reporting, and at this point every
    //    value has already been validated and any errors collected

    // array:: [VDATA] -> VDATA
    array:: function(vdata_array) {
      // TODO: handle Optional correctly in arrays
      //       will probably need to convert to mapWithIndex
      value: [item.value for item in vdata_array],
      errors+: combine([item.errors for item in vdata_array]),
    },

    // object:: {KEY: VDATA ...} -> VDATA
    object:: function(vdata_map) {
      value+: {
        [field]: vdata_map[field].value
        for field in std.objectFields(vdata_map)
        if !(maybeGet(vdata_map[field], 'optional', false) && !contains(vdata_map[field], 'value'))
      },
      errors+: combine([
        field_vdata.errors
        for field_vdata in std.objectValues(vdata_map)
        if !(maybeGet(field_vdata, 'optional', false) && !contains(field_vdata, 'value'))
      ]),
    },
  },

  // Helper to make it easy to write basic custom conditionals
  // Return true/non-string for validness
  CustomValidator:: function(customFunction, err='%s', name='CustomValidator')
    function(vdata)
      vdata { schemaDescription: name } +
      (
        if !std.objectHas(vdata, 'value') then
          $.withMissingError
        else
          local result = customFunction(vdata.value);
          if std.type(result) == 'boolean' && result then
            vdata
          else if std.type(err) == 'string' then
            $.withError(err % std.toString(vdata.value))
          else
            $.withError({ result:: result, value:: vdata.value } + err)
      ),

  CustomFilter:: function(customFunction, customError, name='CustomFilter')
    function(vdata)
      vdata
      { schemaDescription: name } + (
        if !std.objectHas(vdata, 'value') then
          $.withMissingError
        else if !std.member(['array', 'object'], std.type(vdata.value)) then
          $.withError({
            'error': 'CustomFilter only applicable to arrays/objects',
          })
        else
          // TODO: add check that customFunction has one vs two args for array vs map
          local resultMap =
            if std.type(vdata.value) == 'array' then
              std.map(customFunction, vdata.value)
            else
              [
                customFunction(field, vdata.value[field])
                for field in std.objectFields(vdata.value)
              ];
          local result = std.foldl(
            // If all booleans, result is true if all true, else false
            // If any non-booleans, assume result is error and aggregate results as list
            function(a, b)
              local curr = std.type(a), return = std.type(b);
              if curr == 'boolean' && return == 'boolean' then
                a && b
              else if curr == 'boolean' && return != 'boolean' then
                [b]
              else if curr != 'boolean' && return == 'boolean' then
                a
              else
                a + [b]
            ,
            resultMap,
            true
          );
          if result == true then
            {}
          else
            // TODO: add error check that customError is an object
            $.withError({ result:: result, value:: vdata.value } + customError)
      ),

  // Check that all values in the array match the same schema (similar to Array<T> in java)
  // TODO: We should probably make this the default when encountering `[...]` syntax in schema
  //       It's extremely rare that anyone would want an array with an exact length and diferrent types for each positional element
  Array:: function(schema)
    function(vdata)
      vdata
      { schemaDescription: 'array[%s]' % $.schemaToString(schema) } +
      if !std.objectHas(vdata, 'value') then
        $.withMissingError
      else if std.type(vdata.value) != 'array' then
        $.withError({
          actual: std.type(vdata.value),
        })
      else
        $.bind.array(
          std.mapWithIndex(
            function(index, _) $.validate($.bind.index(vdata, index),
                                          schema),
            vdata.value
          )
        ),

  // Check that all fields in the data match the same schema (similar to Map<String,T> in java)
  MapOf:: function(schema)
    function(vdata)
      vdata
      { schemaDescription: 'map{%s}' % $.schemaToString(schema) } +
      if !contains(vdata, 'value') then
        $.withMissingError
      else
        if std.type(vdata.value) != 'object' then
          $.withError({
            actual: std.type(vdata.value),
            value: vdata.value,
          })
        else
          $.bind.object({
            [field]: $.validate($.bind.fieldValue(vdata, field), schema)
            for field in std.objectFields(vdata.value)
          })
  ,


  // Validate if exists, otherwise ignore
  // NOTE: Optional is special-cased by necessity
  // TODO: Allow specifying a default value
  Optional:: function(schema)
    function(vdata)
      $.validate(vdata, schema) +
      { optional: true },


  And:: function(schemaA, schemaB)
    function(vdata)
      vdata {
        schemaDescription:
          $.schemaToString(schemaA) + ' && ' + $.schemaToString(schemaB),
      } +
      if !contains(vdata, 'value') then
        $.withMissingError
      else
        local resultA = $.validate(vdata, schemaA);
        if std.length(resultA.errors) == 0 then
          $.validate(vdata, schemaB)
        else
          resultA,


  // Check data against all provided schemas, and return the result of the first one that matches (or error if none)
  Either:: function(schemas)
    function(vdata)
      local results = std.map(
        function(schema) $.validate(vdata, schema), schemas
      );
      local valid = std.filter(
        function(_vdata) std.length(_vdata.errors) == 0, results
      );
      vdata {
        schemaDescription:
          std.join(' OR ', ([$.schemaToString(s) for s in schemas])),
      } +
      if !contains(vdata, 'value') then
        $.withMissingError
      else if std.length(valid) == 0 then
        $.withError({
          actual:
            std.type(vdata.value),
          value:
            (if std.type(vdata.value) == 'string'
             then '"' + vdata.value + '"'
             else std.toString(vdata.value)),
          //failures:
          //std.manifestJsonEx(
          //combine([result.errors for result in results]),
          //indent='  '
          //),
        })
      else
        valid[0],

  Enum:: function(literalsArray)
    function(vdata)
      vdata {
        schemaDescription:
          '{%s}' % std.join(', ', literalsArray),
      } +
      if !std.objectHas(vdata, 'value') then
        $.withMissingError(vdata)
      else
        if !std.member(literalsArray, vdata.value) then
          $.withError({
            'error': 'Value not allowed',
            value: std.toString(vdata.value),
          })
        else {},

  // Don't remove extra fields not in schema
  ExtensibleMap:: function(schema)
    function(vdata)
      vdata +
      if std.type(schema) != 'object' || std.type(vdata.value) != 'object' then
        // TODO: is this valid without a schemaDescription def?
        $.withError({
          'error': 'ExtensibleMap requires object schema, got %s instead' % std.type(schema),
        })
      else
        $.validate(vdata, schema + {
          [unknownField]: 'any'
          for unknownField in std.setDiff(
            std.objectFields(vdata.value),
            std.objectFields(schema)
          )
        }),

  // Error if any fields in input but not in schema
  // NOTE: this also de facto freezes the schema for the object
  StrictMap:: function(schema)
    function(vdata)
      // Pass through to normal validation first, then check fields
      $.validate(vdata, schema) +
      { schemaDescription: 'StrictMap' } +
      if std.type(schema) != 'object' || std.type(vdata.value) != 'object' then
        $.withError({
          'error': 'StrictMap requires object schema, got %s instead' % std.type(schema),
        })
      else
        local diff = std.setDiff(
          std.objectFields(vdata.value),
          std.objectFields(schema)
        );
        if std.length(diff) != 0 then
          $.withError({
            err: 'Unknown fields in strict map',
            fields: diff,
          })
        else
          {},

  validate:: function(vdata, schema, err=null)  // => VDATA
    local dataType = std.type(vdata.value);
    local schemaType = std.type(schema);

    vdata
    { schemaDescription: $.schemaToString(schema) } +
    { errors+: if err != null then [err] else [] } +

    // This must be done first, or else extensions like Optional will never
    // get the opportunity to handle missing values before it becomes an error
    // Caveat is this means all extension handlers *MUST* handle the possibility
    // of a missing value themselves!
    if schemaType == 'function' then
      schema(vdata)

    // Check if field is missing
    else if !contains(vdata, 'value') then
      $.withError({
        'error': 'required field does not exist!',
      })

    else if schema == 'any' then
      {}

    // Recurse into object schema
    else if schemaType == 'object' && dataType == 'object' then
      $.bind.object({
        [field]: $.validate(
          $.bind.fieldValue(vdata, field),
          schema[field]
        )
        for field in std.objectFields(schema)
      })

    // Recurse into fixed array schema - this will likely be a rare case
    // as most arrays are not fixed length/positional
    // TODO: Consider making this an alias for Array(...) instead
    //       and use a special type for fixed length / positional arrays
    else if schemaType == 'array' && dataType == 'array' then
      if std.length(schema) != std.length(vdata.value) then
        $.withError({
          'error': 'Array length does not match schema',
          expected: std.length(schema),
          actual: std.length(vdata.value),
        })
      else
        $.bind.array(
          std.mapWithIndex(
            function(index, _)
              $.validate($.bind.index(vdata, index), schema[index])
            , schema
          )
        )

    else if std.member(['array', 'object'], schema) && std.member(['array', 'object'], dataType) then
      {}

    else
      if dataType == schema then
        {}
      else
        $.withError({
          path: $.contextPath(vdata.context),
          actual: dataType,
          value: (if dataType == 'string'
                  then '"' + vdata.value + '"'
                  else std.toString(vdata.value)),
        }),

  RawValidate:: function(input, schema)
    $.validate({ errors+: [], value: input, context: [] }, schema),

  JsonValidate:: function(data, schema)
    local result_vdata = self.RawValidate(data, schema);
    if std.length(result_vdata.errors) > 0 then
      { errors+: result_vdata.errors }
    else
      result_vdata.value
  ,

  Validate:: function(data, schema)
    local result_vdata = self.RawValidate(data, schema);
    if std.length(result_vdata.errors) > 0 then
      error '\n' + prettyPrintErrors(result_vdata.errors)
    else
      result_vdata.value,

  // Wrapper
  Validator:: function(schema)
    function(input)
      $.Validate(input, schema),
}
