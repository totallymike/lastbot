package require xml
package require tdom
package require http

# File in which irc hosts are matched with last.fm usernames
set nickfile "/home/mike/irchosts.ini"

putlog "Welcome to lastbot!"

global nicklist

set last(char) "%"
set last(who) "-"
set last(key) "cb6d5c415b4e5009fcb76e86ca06f7b1"
set last(root) "http://ws.audioscrobbler.com/2.0/?method="

bind pub $last(who) $last(char)np np 

proc init_nicks {} {
	global nickfile
	global nicklist
	if { [file exists $nickfile] } {
		set handle [open $nickfile r]
		putlog "Initialising [file tail $nickfile]."
		while { [gets $handle line] } {
			set temp [split $line ":"]
			set nicklist([lindex $temp 0]) [lindex $temp 1]
		}
		close $handle
	} else {
		putlog "[file tail $nickfile] does not exist"
	}

}
init_nicks

proc get_nick { $host $nick } {
	global nicklist
	if {[info exists $nicklist($host)]} {
		return $nicklist($host)
	} else {
		return $nick
	}
}


proc np {nick host hand chan arg} {
	global last
	set args [split $arg]
	set target [get_nick $host $nick]
	if { [llength $args] > 1 || [string match "help" [lindex $args 0]] } {
		puthelp "privmsg $chan :Use: $last(char)np \[nick\]"
		return 1
	} elseif { [llength $args] == 1} {
		set target [lindex $args 0]
	}

	set token [::http::geturl "$last(root)user.getRecentTracks&user=$target&limit=1&api_key=$last(key)"]
	upvar #0 $token state
	putlog $state(body)

	set doc [dom parse $state(body)]
	set root [$doc documentElement]

	set command "$target "

	set node [[$root firstChild] firstChild]

	if {[$node hasAttribute nowplaing]} {
		append command "$is now playing "
	} else {
		append command "last played "
	}

	set artist [[$node firstChild] firstChild]
	set track [[[$node firstChild] nextSibling] firstChild]
	set newartist [$artist data]
	set newtrack [$track data]

	append command "[$track data], by [$artist data]."

	::http::cleanup $token

	putserv "privmsg $chan :$command"

	set url "$last(root)track.getinfo&artist=$newartist&track=$newtrack&api_key=$last(key)"
	regsub -all -- { } $url {%20} url
	putlog $url
	set token [::http::geturl $url]
	upvar #0 $token state
	putlog $state(body)

	set doc [dom parse $state(body)]
	set root [$doc documentElement]

	set name [[$root selectNodes /lfm/track/name/text()] data]
	set listeners [[$root selectNodes /lfm/track/listeners/text()] data]
	set playcount [[$root selectNodes /lfm/track/playcount/text()] data]
	
	set tags [$root selectNodes /lfm/track/toptags/tag/name/text()]

	set command "$name has been played $playcount times by $listeners listeners.  It has "
	if {[llength $tags]} {
		append command "the following tags: "
		if {[llength $tags] > 5} {
			set max 5
		} else {
			set max [llength $tags]
		}
		for { set i 0 } { $i < $max } { incr i } {
			if { $i < $max - 1 } {
				append command "[[lindex $tags $i] data], "
			} else {
				append command "[[lindex $tags $i] data]."
			}
		}
	} else {
		append command "no tags."
	}

	putserv "privmsg $chan :$command"

	putlog $name

	
	return 0
}
proc urlencode {url} {
	set url [string trim $url]
	# % goes first ... obviously :)
	regsub -all -- {\%} $url {%25} url
	regsub -all -- { } $url {%20} url
	regsub -all -- {\&} $url {%26} url
	#regsub -all -- {\!} $url {%21} url
	regsub -all -- {\@} $url {%40} url
	regsub -all -- {\#} $url {%23} url
	regsub -all -- {\$} $url {%24} url
	regsub -all -- {\^} $url {%5E} url
	#regsub -all -- {\*} $url {%2A} url
	#regsub -all -- {\(} $url {%28} url
	#regsub -all -- {\)} $url {%29} url
	regsub -all -- {\+} $url {%2B} url
	regsub -all -- {\=} $url {%3D} url
	
	regsub -all -- {\\} $url {%5C} url
	regsub -all -- {\/} $url {%2F} url
	regsub -all -- {\|} $url {%7C} url
	regsub -all -- {\[} $url {%5B} url
	regsub -all -- {\]} $url {%5D} url
	regsub -all -- {\{} $url {%7B} url
	regsub -all -- {\}} $url {%7D} url
	#regsub -all -- {\.} $url {%2E} url
	regsub -all -- {\,} $url {%2C} url 
	#regsub -all -- {\-} $url {%2D} url
	#regsub -all -- {\_} $url {%5F} url
	#regsub -all -- {\'} $url {%27} url
	#Need : to make define:, movie: etc work 
	#regsub -all -- {\:} $url {%3A} url
	regsub -all -- {\;} $url {%3B} url
	regsub -all -- {\?} $url {%3F} url
	regsub -all -- {\"} $url {%22} url
	
	regsub -all -- {\<} $url {%3C} url
	regsub -all -- {\>} $url {%3E} url
	regsub -all -- {\~} $url {%7E} url
	regsub -all -- {\`} $url {%60} url
	return $url
}
