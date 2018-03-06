# macOS only - reads JSON from clipboard and puts it back on clipboard as pretty-printed Ruby hash
# Useful for copying json data out as hashes for mocking out responses in tests
i2,o2,e2 = Open3.popen3('pbpaste'); i, o, e = Open3.popen3('pbcopy'); PP.pp(JSON.parse(o2.read), i); i.close; o2.close
