Red [
	description: {
		Unit testing library
		
		It tests entire files, creating a clean context for them plus
		injecting `assert`, `expect` and `expect-error` functions. Then,
		test cases are added with description and test code, which should
		include one of mentioned functions. Output is captured. Test results
		can be printed out, or retrieved as a map. You can limit number
		of tests performed, the rest is ignored.
		
		Usage:
		
		Red []
		#include %testlib.red
		test-init/limit %tested-script.red 5  ; execute first 5 tests
		test "Tested function returns string" [
			expected-argument: 123
			expect string! [type? tested-function expected-argument]
		]
		test "We live in a sane world" [
			print "This output will be captured."
			assert [1 + 1 = 2]
			expect-error 'math [1 / 0]
		]
		test "Tested function gives error on none!" [
			illegal-argument: none
			expect-error 'script [tested-function illegal-argument]
		]
		probe test-results
		test-results/print
	}
	author: "loziniak"
]


context [
	tested: ignore-after: test-file: results: output: none
	
	set 'test-init function [
		"Initializes the testlib for a tested file."
		file	[file!]		"File being tested. It's executed in isolated, clean context, only with assert, expect and expect-error functions."
		/limit
			ia	[integer!]	"All tests are ignored after this number"
	] [
		self/tested: 0
		self/ignore-after: either limit [ia] [none]
		self/test-file: file
		self/results: copy []
		self/output: copy ""
	]

	sandbox!: context [
	
		assert: function [
			"Check if the code resolves to true."
			code [block!]
			/local result
		] [
			res: last results

			set/any 'result do code
			either :result = true [
				res/status: 'pass
			] [
				res/status: 'fail
				throw/name none 'expect-fail
			]
			
			:result
		]
	
		expect: function [
			"Check if the code resolves to expected value."
			expectation [any-type!]
			code [block!]
			/local result
		] [
			res: last results
			res/expected: :expectation

			set/any 'result do code
			res/actual: :result
		
			either :result = :expectation [
				res/status: 'pass
			] [
				res/status: 'fail
				throw/name none 'expect-fail
			]
			
			:result
		]

		expect-error: function [
			"Checks if the code results in an error of expected type, optionally also a specific message."
			type	[word!]		"Expected type, like 'user or 'math"
			code	[block!]
			/message
				msg	[string!]	"Optional message check. Type has to be 'user"
			/local result result-or-error
		] [
			returned-error?: no
			set/any 'result-or-error try [
				set/any 'result do code
				returned-error?: yes
				:result
			]

			res: last results
			res/actual: :result-or-error
			res/expected: compose [type: (type)]
			if message [append res/expected compose [id: 'message arg1: (msg)]]
			
			either all [
				error? :result-or-error
				not returned-error?
				result-or-error/type = type
				any [
					not message
					all [
						result-or-error/id = 'message
						result-or-error/arg1 = msg
					]
				]
			] [
				res/status: 'pass
			] [
				res/status: 'fail
				throw/name none 'expect-fail
			]
			
			:result-or-error
		]
	]

	set 'test function [
		"Executes a test in isolated context."
		summary [string!]	"Text describing what's tested"
		code [block!]		"Code to run, containing assert, expect and expect-error functions invocations"
		/extern
			tested
	] [
		append results result: make map! compose/only [
			summary: (summary)				;@@ [string!]
			test-code: (copy code)			;@@ [block!]
			status: none					;@@ [word!] : 'pass | 'fail | 'error | 'ignored
			;-- expected					(optional field)
			;-- actual						(optional field)
			;-- output						(optional field)
		]
	
		either any [
			none? ignore-after
			tested < ignore-after
		] [
			clear output
			old-functions: override-console
		
			exercise: make sandbox! load test-file
			code: bind code exercise
			uncaught?: yes
			outcome: catch [
				outcome: try [
					catch/name [
						do code
					] 'expect-fail
					none
				]
				uncaught?: no
				outcome
			]			
			
			case [
				error? outcome [
					result/status: 'error
					result/actual: outcome
				]
				uncaught? [
					result/status: 'error
					result/actual: make error! [type: 'throw id: 'throw arg1: outcome]
				]
			]

			restore-console old-functions
			result/output: copy output
		] [
			result/status: 'ignored
		]

		tested: tested + 1
		()
	]
	
	set 'test-results function [
		"Returns a block of all tests results as maps. Map's keys: summary, test-code, status, expected, actual, output."
		/print		"Print a summary instead"
	] [
		either print [
			foreach result self/results [
				system/words/print rejoin [
					pad/with copy result/summary 40 #"."
					"... "
					switch result/status [
						pass	["✓"]
						fail	[rejoin [
								{FAILED.}
								either find result 'expected [rejoin [
									{ Expected: } result/expected
									either find result 'actual [rejoin [
										{, but got } result/actual
									]] []
								]] []
								newline
								result/output
							]]
						error	[rejoin [
								newline
								result/output
								form result/actual
							]]
						ignored	["(ignored)"]
					]
				]
			]
		] [
			self/results
		]
	]


	override-console: function [] [
		old-functions: reduce [:prin :print :probe]

		system/words/prin: function [value [any-type!]] [
			append self/output form :value
			return ()
		]
		system/words/print: function [value [any-type!]] [
			append self/output reduce [form :value #"^/"]
			return ()
		]
		system/words/probe: function [value [any-type!]] [
			append self/output reduce [mold :value #"^/"]
			return :value
		]
		return old-functions
	]

	restore-console: function [old-functions [block!]] [
		set [prin print probe] old-functions
	]

]
