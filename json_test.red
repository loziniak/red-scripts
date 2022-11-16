Red []

do %test.red
do %json.red


json-test: make suite []
json-test/expect #(abc: "def") [parser/process {{"abc":"def"}}]
json-test/expect #(abc: nul) [parser/process "{^"abc^":null}"]
json-test/expect "{^"abc^":null}" [generator/process parser/process "{^"abc^":null}"]
json-test/expect #(abc: "nitek^^") [parser/process {{"abc":"nitek^^"}}]
json-test/expect #(abc: {text with "quotes"}) [parser/process {{"abc":"text with \"quotes\""}}]


result: json-test/run
probe result
