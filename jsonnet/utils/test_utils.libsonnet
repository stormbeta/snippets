{
  //sjhema:: (import '../templates/helpers/schema.libsonnet') { mode: 'json' },
  //TestCase:: function(object) $.schema.TypeCheck(self.schema.All([
  //'object',
  //$.schema.MutuallyExclusiveFields(['value', 'values']),
  //$.schema.MutuallyExclusiveFields(['equals', 'match']),
  //]), object, mode='error'),
  //TestCase:: $.schema.MakeType('TestCase', self.schema.All([
  //'object',
  //$.schema.MutuallyExclusiveFields(['value', 'values']),
  //$.schema.MutuallyExclusiveFields(['equals', 'match']),
  //])),
  // TODO: Implement pattern like this for easier type checking?
  //TestCase:: $.schema.MakeType('TestCase', $.TestCaseType),


  schema:: (import 'schema.libsonnet') { mode: 'json' },
  local s = $.schema,

  // TODO: This is cool and all, but it doesn't produce the most readable error if
  //       for example someone uses the wrong field name.
  //       A StrictMap + checking exclusivity ourselves is probably better
  //TestCaseType:: s.All([
  //'object',
  //s.ExclusiveOr(['value', 'values']),
  //s.ExclusiveOr(['equals', 'match']),
  //]),
  // TODO: StrictMap is what we want BUT it's not compatible with Optional yet
  TestCaseType:: s.All([
    s.AllowedFields(['value', 'values', 'match', 'equals']),
    s.Validator('', function(case) {
      local v0 = !('value' in case != 'values' in case),
      local v1 = !('match' in case != 'equals' in case),
      result: v0 && v1,
      'error': (if v0 then 'Test case must specify value or values to test against!' else '') + (if v1 then 'Test case must specify either equals or match patterns!' else ''),
    }),
  ]),
  TestSuiteType:: s.MapOf(
    s.Either([
      $.TestCaseType,
      s.ArrayOf($.TestCaseType),
    ])
  ),


  //checkedGet:: function(collection, path, default={}, handler=function(v) v)
  //utils.safeGet(collection, path, std.trace("[WARNING]: Value could not be found
  //,

  // TODO: Should use RawValidate instead
  // TODO: Collect over all tests, injecting test group/name for pretty output
  //       Need to collect ALL tests as local, then iterate down
  //TestSuite:: function(_tests)
  TestSuite:: function(tests)
    //local tests = $.schema.MakeType('TestSuite', $.TestSuiteType)(_tests);
    std.trace('\n' + std.join('\n', [
      local check = function(case)
        //local case = $.TestCase(_case);
        local values = if 'values' in case then case.values else [case.value];
        if !std.isObject(case) then
          error std.toString(case) + ' is not a test case object!'
        else if !('value' in case != 'values' in case) then
          //if !('value' in case != 'values' in case) then
          error 'Test case must specify value or values to test against!'
        else if !('match' in case != 'equals' in case) then
          error 'Test case must specify either equals or match patterns'
        else if 'match' in case then
          [$.schema.Validate(value, case.match) for value in values]
        else if 'equals' in case then
          [$.schema.Validate(value, $.schema.Equals(case.equals)) for value in values];
      local result =
        std.flatMap(
          function(test) check(test),
          if std.type(tests[name]) == 'array' then
            [testCase for testCase in tests[name]]
          else
            [tests[name]]
        );
      local failed = std.filter(
        function(t) std.isObject(t) && 'errors' in t,
        result
      );
      local numTests = std.length(result);
      '=== %s/%s Passed ===' % std.map(std.toString, [numTests - std.length(failed), std.length(result)]) +
      if std.length(failed) > 0
      then ' FAILED: ' + name + '\n' + $.schema.prettyPrintErrors(std.flatMap(function(x) x.errors, failed), '  ')
      else ' PASSED: ' + name
      for name in std.objectFields(tests)
    ]), 'Tests passed!'),
