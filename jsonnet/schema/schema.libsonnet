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

Union([SCHEMAS...])
  Will check that data matches at least one of the provided schemas

Custom(FUNCTION(DATA)->[ERRORS...])
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
  // jq-style representation of current context in object
  // @context: [{type: field|index|FIELD_MISSING, value: ...}]
  contextString:: function(context)
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

  addError:: function(vdata, message, opts={})
    vdata {
      errors+: [{
        path: $.contextString(vdata.context),
        'error': message,
        //(if maybeGet(opts, 'type', false) then ' TYPE: %s\n' % std.type(vdata.value) else '') +
      }],
    },

  missingError:: function(vdata)
    $.addError(vdata, 'ERROR: required field does not exist!\n'),

  // Behold, the power of monads!
  // NOTE: this should maybe be exposed in the library better
  Validator:: {
    local UnitError = [],
    local UnitContext = [],

    missingError:: function(vdata)
      vdata {
        errors+: [{
          path: $.contextString(vdata.context),
          'error': 'required field does not exist!',
        }],
      },

    // DATA => VDATA
    wrap:: function(data) {
      value: data,
      errors: UnitError,
      context: UnitContext,
    },

    // VDATA => DATA else ERRORS
    unwrap:: function(vdata)
      if std.length(vdata.errors) == 0
      then vdata.value
      else error (std.foldl(
                    function(sum, err) sum + '\n' + err,
                    vdata.errors,
                    ''
                  )),

    // [VDATA] => VDATA
    rewrapArr:: function(vdata_array) {
      // TODO: handle Optional correctly in arrays
      //       will probably need to convert to mapWithIndex
      value: [item.value for item in vdata_array],
      errors: combine([item.errors for item in vdata_array]),
    },

    // {K: VDATA, ...} => VDATA
    rewrapObj:: function(vdata_map) {
      value: {
        [field]: vdata_map[field].value
        for field in std.objectFields(vdata_map)
        if !(maybeGet(vdata_map[field], 'optional', false) && !contains(vdata_map[field], 'value'))
      },
      errors: combine([
        field_vdata.errors
        for field_vdata in std.objectValues(vdata_map)
        if !(maybeGet(field_vdata, 'optional', false) && !contains(field_vdata, 'value'))
      ]),
    },
  },

  // Helper to make it easy to write basic custom conditionals
  Custom:: function(custom_function)
    function(validate, vdata)
      if !std.objectHas(vdata, 'value') then
        $.missingError(vdata)
      else
        local result = custom_function(vdata.value);
        if result == true || std.type(result) != 'string'
        then vdata
        else $.addError(vdata, result),

  // Check that all values in the array match the same schema (similar to Array<T> in java)
  Array:: function(schema)
    // TODO: Handle missing value case
    function(validate, maybe_vdata)
      { context: maybe_vdata.context } +
      if std.type(maybe_vdata.value) != 'array' then
        // TODO: We need a safe way to toString schemas that might contain functions
        $.addError(maybe_vdata, 'EXPECTED: [%s]' % 'tmp', { type: true })
      else
        $.Validator.rewrapArr(
          std.mapWithIndex(
            function(index, _)
              validate(
                {
                  value: maybe_vdata.value[index],
                  errors: [],
                  context: maybe_vdata.context + [{ type: 'index', value: index }],
                },
                schema
              )
            , maybe_vdata.value
          )
        ),

  // Check that all fields in the data match the same schema (similar to Map<String,T> in java)
  MapOf:: function(schema)
    // TODO: What if vdata.value is not an object?
    function(validate, maybe_vdata)
      { context: maybe_vdata.context } +
      if contains(maybe_vdata, 'value') then
        $.Validator.rewrapObj(
          {
            [field]: validate(
              {
                value: maybe_vdata.value[field],
                errors: [],  // Strictly speaking, this should be UnitError incase type of errors changes
                context: maybe_vdata.context + [{ type: 'field', value: field }],
              },
              schema
            )
            for field in std.objectFields(maybe_vdata.value)
          },
        )
      else $.Validator.missingError(maybe_vdata),

  // Validate if exists, otherwise ignore
  Optional:: function(schema)
    function(validate, maybe_vdata)
      validate(maybe_vdata, schema) { optional: true },

  // Check data against all provided schemas, and return the result of the first one that matches (or error if none)
  Union:: function(schemas)
    function(validate, maybe_vdata)
      local results =
        std.filter(
          function(_vdata) std.length(_vdata.errors) == 0,
          std.map(
            function(schema) validate(maybe_vdata, schema),
            schemas
          )
        );
      if !contains(maybe_vdata, 'value') then
        $.Validator.missingError(maybe_vdata)
      else if std.length(results) == 0 then
        maybe_vdata {
          // TODO: KNOWN BUG - if schemas contain a function, this will break!
          errors+:
            [{
              path: $.contextString(maybe_vdata.context),
              expected: 'ANY OF ' + std.toString(schemas),
              actual: std.type(maybe_vdata.value),
              value: (if std.type(maybe_vdata.value) == 'string'
                      then '"' + maybe_vdata.value + '"'
                      else std.toString(maybe_vdata.value)),
            }],

        }
      else
        results[0],

  Enum:: function(literalsArray)
    // TODO: handle missing vdata.value case
    function(validate, maybe_vdata)
      if std.member(literalsArray, maybe_vdata.value) then
        maybe_vdata
      else
        maybe_vdata {
          errors+: [{
            path: $.contextString(maybe_vdata.context),
            expected: 'Literal matching one of ' + std.toString(literalsArray),
            actual: std.toString(maybe_vdata.value),
          }],
        },

  // TODO: This isn't safe to print out without unwrapping
  //       Jsonnet is lazily-evaluated, so it might try to parse missing data if you force it to
  //       print out the entire object
  RawValidate:: function(input, schema)
    local validate = function(vdata, schema)  // => VDATA
      local dataType = std.type(vdata.value);
      local schemaType = std.type(schema);

      // This must be done first in order to handle Optional values correctly
      // This also means all extension validator functions MUST be able to handle
      // the value field being missing!
      if schemaType == 'function' then
        schema(validate, vdata)

      else if !contains(vdata, 'value') then
        {
          errors+: [{
            path: $.contextString(vdata.context),
            'error': 'required field does not exist!',
          }],
        }

      else if schema == 'any' then
        vdata

      else if schemaType == 'object' && dataType == 'object' then
        // TODO: additional validator to force strict checking
        //       i.e. data has no fields that aren't in schema
        // TODO: unknown fields in the data are silently ignored/dropped, which probably isn't desirable default behavior
        { context: vdata.context }
        + $.Validator.rewrapObj(
          {
            [field]:
              validate(
                (if contains(vdata.value, field) then
                   { value: vdata.value[field] }
                 else {})
                + {
                  errors: [],  // TODO: should be Validator.UnitError
                  context: vdata.context + [{ type: 'field', value: field }],
                },
                schema[field]
              )
            for field in std.objectFields(schema)
          },
        )

      else if schemaType == 'array' && dataType == 'array' then
        // TODO: Add check that arrays are of equal length
        //       Alternatively, pass empty missing value field vdata for indexes not in input data?
        { context: vdata.context } +
        $.Validator.rewrapArr(
          std.mapWithIndex(
            function(index, _)
              validate(
                {
                  value: vdata.value[index],
                  errors: [],
                  context: vdata.context + [{ type: 'index', value: index }],
                },
                schema[index]
              )
            , schema
          )
        )

      else if std.member(['array', 'object'], schema) && std.member(['array', 'object'], dataType) then
        vdata

      else
        if dataType == schema then
          vdata
        else
          vdata {
            errors+: [{
              path: $.contextString(vdata.context),
              expected: schema,
              actual: dataType,
              value: (if dataType == 'string'
                      then '"' + vdata.value + '"'
                      else std.toString(vdata.value)),
            }],
          };
    validate($.Validator.wrap(input), schema),

  JsonValidate:: function(data, schema)
    local result_vdata = self.RawValidate(data, schema);
    if std.length(result_vdata.errors) > 0 then
      { errors: result_vdata.errors }
    else
      result_vdata.value
  ,

  Validate:: function(data, schema)
    local result_vdata = self.RawValidate(data, schema);
    if std.length(result_vdata.errors) > 0 then
      error '\n' + prettyPrintErrors(result_vdata.errors)
    else
      result_vdata.value,
  //$.Validator.unwrap(
  //self.RawValidate(data, schema)
  //),
}