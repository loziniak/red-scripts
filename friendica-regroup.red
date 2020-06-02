Red [
	Description: {Script to sort contacts in Friendica groups by frequency of posting}
	Author: "loziniak@o2.pl"
	Dependency: https://github.com/loziniak/red-scripts/blob/master/http.red
	File: %friendica-regroup.red
	License: BSD-3
]

comment {
	TODO:

	-

	CHANGELOG:

	2020.03.26 v1.1
	* all with 0 posts go down
	* group with posts below treshold don't lose users

	2020.03.25 v1.0
}


;--
;-- CONFIG
;--

; Group ids. Has to start with none, group ids from most to less ferquent posts
; example:
;   frequency-grades: [none 74 73 63 61 62 75]
; "none" is a main feed
; group 74 will eventually contain most-frequent posters, while group 75 – least-frequent
frequency-grades: [none your-group-ids-here]

; Friendica host, like "forum.friendi.ca" or "libranet.de"
friendica-host: "your-node-here"

; login that you provide to Friendica's login form
friendica-username: "your-login-here"

; password that you provide to Friendica's login form
friendica-password: "your-password-here"




#include %http.red
random/seed now/time

digit: charset [#"0" - #"9"]
hex: charset [
	#"0" - #"9"
	#"a" - #"f"
	#"A" - #"F"
]


display-login-form: function [
	/extern cookie
] [
	req: make request compose [
		url: (rejoin ["https://" friendica-host "/"])
	]

	req/execute

	phpsessid: select req/response/headers "Set-Cookie"
	probe cookie: phpsessid: copy/part  find phpsessid "PHPSESSID="  find phpsessid ";"
]


login: function [
	/extern cookie
] [
	req: make request [
		url: rejoin ["https://" friendica-host "/login"]
		method: 'POST
		data: rejoin [
			"auth-params=login&username="
			friendica-username
			"&password="
			friendica-password
			"&openid_url=&submit=Login&remember=0&remember=1"]
		urlencode-data: false
	]

	req/headers: make map! compose [
		Cookie: (rejoin ["cncookiesaccepted=1; " cookie])

		Host: (friendica-host)
		Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
		Accept-Language: "en-US,en;q=0.5"
		Referer: (rejoin ["https://" friendica-host "/"])
		Connection: "keep-alive"
	]

	req/execute

	;probe req

	friendica: select req/response/headers "Set-Cookie"
	probe friendica:  copy/part  find friendica "Friendica="  find friendica ";"		;@@ DRY
	cookie: rejoin [cookie "; " friendica]

	unless req/response/status = 302 [
		probe req
		halt
	]
]


scrape-group-into: function [
	users-blk [block!]
	grp-name [integer! word!]
	/extern
		cookie [string!]
		add-tokens [block!]
] [
;	probe users-blk
;	probe grp-name
;	probe type? grp-name

	req: make request [
		url: rejoin ["https://" friendica-host "/group/" grp-name]
		method: 'GET
	]

	req/headers: make map! compose [
		Cookie: (rejoin ["cncookiesaccepted=1; " cookie])

		Host: (friendica-host)
		Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
		Accept-Language: "en-US,en;q=0.5"
		Connection: "keep-alive"
	]

	req/execute

;	probe req/response

	user-rule: [
		[
			[thru {<li class="members active">} (active?: true)]
			|
			(active?: false)
		]
		thru {contact-entry-wrapper-}
		[
			"{$id}"
			|
			copy id   some digit
			[
				thru {groupChangeMember(} some digit "," some digit ",'"
				copy change-token [some digit "." some hex]
				|
				(change-token: none)
			]
			thru {<div class="contact-entry-name"}
			thru {<a href="}
			copy url  any [not #"^"" skip]
			{">}
			copy name any [not #"<" skip]
			(
				either any [
					active?
					none? grp-name
					'none = grp-name
				] [
					append users-blk new-line reduce [0 id name url change-token] true
				] [
					append add-tokens new-line reduce [
						;as-pair  to integer! id  to integer! grp-name
						rejoin [grp-name ":" url]
						id
						change-token
						name
					] true
				]
			)
		]
	]
	probe parse req/response/body [
		thru "viewcontact_wrapper"
		any user-rule
		any skip
	]
	users-blk
]



access: function [
	group [integer! word!]
] [
	to word! append copy "g-" group
]


count-group: function [
	users-blk [block!]
	grp-name [word! integer!]
	/extern
		cookie [string!]
		not-found [block!]
] [
	req: make request [
		url: rejoin ["https://" friendica-host "/network/" grp-name]
		method: 'GET
	]

	req/headers: make map! compose [
		Cookie: (rejoin ["cncookiesaccepted=1; " cookie])

		Host: (friendica-host)
		Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
		Accept-Language: "en-US,en;q=0.5"
		Connection: "keep-alive"
	]

	req/execute

;	probe req/response

	tread-wrappers: 0
	media-headings: 0
	post-rule: [
		thru "tread-wrapper" (tread-wrappers: tread-wrappers + 1)
		thru {<div class="media}
		thru {class="contact-info}
		[
			thru {<h4 class="media-heading">}
			some thru [
				{<a href="} copy url any [not #"^"" skip]
				|
				{</h4>} break
			]
			(media-headings: media-headings + 1)
		]
		(
			either pos: find users-blk url [
				pos: skip pos -3
				change pos (1 + first pos)
				new-line pos true
			] [
				not-found/(grp-name): 1 + either nf: not-found/(grp-name) [nf] [0]
			]
		)
	]

	probe parse req/response/body [
		thru "network-content-wrapper"
		any post-rule
		any skip
	]

	print ["tread-wrappers" tread-wrappers]
	print ["media-headings" media-headings]
]


list-counts: function [
	g [word! integer!]
	/extern users not-found
] [
	grp: users/(access g)
	until [
		print ["  " grp/1 "   " grp/3]
		tail? grp: skip grp 5
	]
	if nf: not-found/:g [
		print ["  " nf    "   " "(not found)"]
	]
]


not-enough-posts?: function [
	grp [integer! word!]
	/extern frequency-grades users not-found
] [
	grp-posts: none
	ppg: copy []
	foreach group-name head frequency-grades [
		posts: either nf: not-found/:group-name [nf] [0]
		g: users/(access group-name)
		while [5 <= length? g] [
			posts: posts + first g
			g: skip g 5
		]
		if grp == group-name [
			grp-posts: posts
		]
		append ppg posts
	]
	if none? grp-posts [
		return false
	]

	sort ppg
	median: either 2 < len: length? ppg [
		last ppg
	] [
		ppg/(len / 2 + 1)
	]

	grp-posts < (median * 6 / 7)
]


add-contact-to: function [
	grp [integer!]
	url [string!]
	/extern
		cookie
		add-tokens
] [
	found: find add-tokens rejoin [grp ":" url]
	if none? found [
		print ["::: add:" url "already exists in" grp]
		return none
	]
	print ["::: add" copy/part found 4]

	req: make request [
		url: rejoin [
			"https://" friendica-host "/group/" grp
			"/" found/2
			"?t=" found/3]
		method: 'GET
	]

	req/headers: make map! compose [
		Cookie: (rejoin ["cncookiesaccepted=1; " cookie])

		Host: (friendica-host)
		Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
		Accept-Language: "en-US,en;q=0.5"
		Connection: "keep-alive"
	]

	req/execute

;	req/response/body: ""
;	probe req/response
	print [req/response/status req/response/status-message]
]


remove-contact-from: function [
	grp [integer!]
	record [block!]
	/extern
		cookie
		add-tokens
] [
	print ["::: remove" grp record/3]

	req: make request [
		url: rejoin [
			"https://" friendica-host "/group/" grp
			"/" record/2
			"?t=" record/5]
		method: 'GET
	]

	req/headers: make map! compose [
		Cookie: (rejoin ["cncookiesaccepted=1; " cookie])

		Host: (friendica-host)
		Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
		Accept-Language: "en-US,en;q=0.5"
		Connection: "keep-alive"
	]

	req/execute

;	req/response/body: ""
;	probe req/response
	print [req/response/status req/response/status-message]
]



;id name url change-token 0

fuzzy: function [a b] [
	case [
		a < b [true]
		a > b [false]
		a = b [random true]
	]
]

move-user: function [
	user [block!]
	src [integer! word!]
	dest [integer! word!]
] [
	unless word? src [
		remove-contact-from src  user
	]
	unless word? dest [
		add-contact-to      dest user/4
	]
]



;--
;-- MAIN LOGIC
;--

display-login-form
login

users: copy []
add-tokens: copy []
foreach group frequency-grades [
	append users reduce [
		access group
		scrape-group-into
			copy []
			group
	]
]
;probe add-tokens

not-found: make map! []
foreach group frequency-grades [
	count-group users/(access group) group
]

;probe users
;probe add-tokens

frequency-grades: head frequency-grades
length-delta: 3 * 5
forall frequency-grades [
	g-current: first frequency-grades
	grp: users/(access g-current)
	sort/skip/compare grp 5 :fuzzy

	probe g-current
	;probe grp
	list-counts g-current

	if all [
		not-enough-posts? g-current
	] [
		print "/// not enough posts. skipping."
		continue
	]

	; move highest up
	unless any [
		head? frequency-grades
		1 > length? grp
		all [
			not not-enough-posts? (g-prev: pick frequency-grades -1)
			(length? users/(access g-prev)) > (length? grp)
		]
	] [
		highest: skip  tail grp  -5
		print ["HIGHEST" copy/part highest 5]
		move-user highest g-current g-prev

		if all [
			2 <= length? grp
			(length? users/(access g-prev)) + length-delta < (length? grp)
		] [
			highest: skip  tail grp  -10
			print ["SECOND HIGHEST" copy/part highest 5]
			move-user highest g-current g-prev
		]
	]

	; move lowest down
	unless any [
		tail? next frequency-grades
		2 > length? grp
		all [
			not not-enough-posts? (g-next: second frequency-grades)
			(length? users/(access g-next)) > (length? grp)
		]
	] [
		removed: 0

		lowest: skip  head grp  (removed * 5)
		print ["LOWEST" copy/part lowest 5]
		move-user lowest g-current g-next
		removed: removed + 1

		if all [
			4 <= length? grp
			(length? users/(access g-next)) + length-delta < (length? grp)
		] [
			lowest: skip  head grp  (removed * 5)
			print ["SECOND LOWEST" copy/part lowest 5]
			move-user lowest g-current g-next
			removed: removed + 1
		]

		while [
			lowest: skip  head grp  (removed * 5)
			zero? lowest/1
		] [
			print ["ZERO POSTS" copy/part lowest 5]
			move-user lowest g-current g-next
			removed: removed + 1
		]
	]
]

