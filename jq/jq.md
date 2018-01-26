# jq cheat sheet and snippets

## Merging and diffing arrays

Given two JSON arrays in a.json and b.json:

a.json: `[1, {a: 1}, "foo", {a: 2}, {b: 1}]`
b.json: `[{a: 1}, "bar", 1, 2]`

```
# Merge arrays (slurp, compact-output)
$ jq -s -c '.[0] + .[1] | unique' a.json b.json
[1,2,"bar","foo",{"a":1},{"a":2},{"b":1}]

# Intersect arrays
$ jq --slurp '.[0] - .[1]' a.json b.json
["foo",{"a":2},{"b":1}]
```

Credit: https://stackoverflow.com/questions/19529688/how-to-merge-2-json-file-using-jq

## Finding fields from structures with arbitrary nesting

Useful when you know a field's name but it's buried in a nested structure

Given JSON object in nested.json

```
{
  "a": {
    "b": {
      "target": "value1"
    }
  },
  "b": [1,2,3],
  "c": {
    "d": {
      "target": "value2"
    }
  }
}
```

```
$ jq '.. | .target? | select(. != null)' nested.json | jq -s -c
["value1","value2"]
```

## Parsing embedded serialized JSON

Useful for things like the Docker Registry v2 API or AWS responses that frequently contain JSON objects serialized to strings inside of other JSON objects

Given file embedded.json:

```
{
  "embedded": "{\"hello\":\"world\"}",
  "normal": {
    "hello": "earth"
  }
}
```

```
# NOTE: you can use 'tostring' for the reverse operation
$ jq -c '.embedded | fromjson'
{"hello":"world"}
```

## Convert between shell-style lists and JSON

Other CLI tools don't necessarily understand JSON, so it's useful to convert back and forth

Given a file 'list':

```
one
two
three
```

```
# -R / --raw-input quotes the input, -s / --slurp turns it into a JSON array
$ cat list | jq -R . | jq -s -c .
["one","two","three"]

# -r / --raw-output to consume the quotes
$ echo '["one","two","three"]' | jq -r '.[]'
one
two
three
```
