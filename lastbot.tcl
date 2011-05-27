package require xml
package require tdom
package require http

# File in which irc hosts are matched with last.fm usernames
set nickfile "/home/mike/irchosts.ini"

putlog "Welcome to lastbot!"

global nicklist

set last(char) "!"
set last(who) "-"
set last(key) "cb6d5c415b4e5009fcb76e86ca06f7b1"
set last(root) "http://ws.audioscrobbler.com/2.0/?method="

proc init_nicks {} {
    global nickfile
    global nicklist
    if { [file exists $nickfile] } {
	set handle [open $nickfile r]
	putlog "Initialising [file tail $nickfile]."
	while { [gets $handle line]  >= 0} {
	    putlog $line
	    set temp [split $line ":"]
	    set nicklist([lindex $temp 0]) [lindex $temp 1]
	}
	close $handle
    } else {
	putlog "[file tail $nickfile] does not exist"
    }

}

proc get_nick { nick } {
    global nicklist
    set host [getchanhost $nick]
    if {[info exists nicklist($host)]} {
	return $nicklist($host)
    } else {
	return $nick
    }
}

proc reg_nick { nick last } {
    global nickfile
    set handle [open $nickfile a+]
    set host [getchanhost $nick]
    if { [string length $host] > 0 } { puts $handle "$host:$last" }
    close $handle
    init_nicks
    return 1
}

proc msg_list {nick host hand arg} {
    global nicklist
    foreach { host lastnick } [array get nicklist] {
	putserv "privmsg $nick :$host => $lastnick"
    }
}

proc register {nick host hand chan arg} {
    global last
    set args [split $arg]

    if { [string match "help" [lindex $args 0]] || [llength $args] > 2 } {
	puthelp	"privmsg $chan :Usage: $last(char)register <ircnick> lastnick. If ircnick is ommitted, lastnick will be registered to you."
	return 0
    }
    if { [llength $args] == 1 } {
	if { [reg_nick $nick [lindex $args 0]] } {
	    putserv "privmsg $chan :[lindex $args 0] registered to $nick."
	} else {
	    putserv "privmsg $chan :Error with registration."
	    return 1
	}
    } elseif { [llength $args] == 2 } {
	if { [reg_nick [lindex $args 0] [lindex $args 1]] } {
	    putserv "privmsg $chan :[lindex $args 1] registered to [lindex $args 0]."
	} else {
	    putserv "privmsg $chan :Error with registration."
	    return 1
	}
    }
}


proc msg_register { nick host hand arg } {
    register $nick $host $hand $nick $arg
}

proc pub_register { nick host hand chan arg } {
    register $nick $host $hand $chan $arg 
}

proc compare { nick host hand chan arg } {
    global last
    set arg [string trimright $arg]
    set args [split $arg]
    set target1 [get_nick $nick]

    if { [llength $args] > 2 || [string match "help" [lindex $args 0]] } {
	puthelp "privmsg $chan :Use $last(char)compare nick \[othernick\].  If second nick is omitted, compare to you."
	return 0
    } elseif { [llength $args] == 1 || [string match "" [lindex $args 1]]} {
	putlog "'[lindex $args 0]'"
	set target2 [get_nick [lindex $args 0]]
	putlog "'$target2'"
	lappend args [lindex $args 0]
	lset args 0 $nick
    } elseif { [llength $args] == 2 } {
	set target1 [get_nick [lindex $args 0]]
	set target2 [get_nick [lindex $args 1]]
    }

    set token [::http::geturl "$last(root)tasteometer.compare&type1=user&type2=user&value1=$target1&value2=$target2&limit=5&api_key=$last(key)"]
    upvar #0 $token state
    putlog $state(url)

    set doc [dom parse $state(body)]
    set root [$doc documentElement]

    if { [string match "failed" [$root getAttribute status]]} {
	putserv "privmsg $chan :[[$root selectNode /lfm/error/text()] data]"
	return 1
    }

    set score [[$root selectNodes /lfm/comparison/result/score/text()] data]
    set score [ expr { int($score * 100) } ]

    set matchcount [[$root selectNodes /lfm/comparison/result/artists] getAttribute matches]
    set matches [$root selectNodes /lfm/comparison/result/artists/artist/name/text()]

    set command "[lindex $args 0] :: [lindex $args 1] = $score%."

    if { [llength $matches] > 0 } {
	append command "  $matchcount matches including "
	for { set i 0 } { $i < [llength $matches] } { incr i } {
	    if { $i < [llength $matches] - 2 } {
		append command "[[lindex $matches $i] nodeValue], "
	    } elseif { $i == [llength $matches] - 2 } {
		append command "[[lindex $matches $i] nodeValue], and "
	    } else {
		append command "[[lindex $matches $i] nodeValue]."
	    }
	}
    } else {
	append command "  No matches whatsoever."
    }
    putlog "After loop"

    putserv "privmsg $chan :$command"

    return 0
}

proc pub_compare { nick host hand chan arg } {
    compare $nick $host $hand $chan $arg
}

proc np {nick host hand chan arg} {
    global last
    set arg [string trimright $arg]
    set args [split $arg]
    set tnick $nick
    set target [get_nick $nick]


    if { [llength $args] > 1 || [string match "help" [lindex $args 0]] } {
	puthelp "privmsg $chan :Use: $last(char)np \[nick\]"
	return 0
    } elseif { [llength $args] == 1} {
	set tnick [lindex $args 0]
	set target [get_nick [lindex $args 0]]
    }

    set token [::http::geturl "$last(root)user.getRecentTracks&user=$target&limit=1&api_key=$last(key)"]
    upvar #0 $token state
    putlog $state(url)

    set doc [dom parse $state(body)]
    set root [$doc documentElement]

    if { [string match "failed" [$root getAttribute status]]} {
	putserv "privmsg $chan :[[$root selectNode /lfm/error/text()] data]"
	return 1
    }
    set command "$tnick "

    set node [[$root firstChild] firstChild]

    if {[$node hasAttribute nowplaying]} {
	append command "is now playing "
    } else {
	append command "last played "
    }

    set artist [[$node firstChild] firstChild]
    set track [[[$node firstChild] nextSibling] firstChild]
    set newartist [urlencode [ $artist data]]
    set newtrack [urlencode [$track data]]

    append command "[$track data], by [$artist data]."

    ::http::cleanup $token

    putserv "privmsg $chan :$command"

    set url "$last(root)track.getinfo&artist=$newartist&track=$newtrack&api_key=$last(key)"
    putlog $url
    set token [::http::geturl $url]
    upvar #0 $token state

    set doc [dom parse $state(body)]
    set root [$doc documentElement]

    set name [[$root selectNodes /lfm/track/name/text()] data]
    set listeners [[$root selectNodes /lfm/track/listeners/text()] data]
    set playcount [[$root selectNodes /lfm/track/playcount/text()] data]
    set ratio [ expr {round( double($playcount) / $listeners) } ]
    
    set tags [$root selectNodes /lfm/track/toptags/tag/name/text()]

    set command "$name has been played $playcount times by $listeners listeners ($ratio:1).  It has "
    if {[llength $tags]} {
	append command "the following tags: "
	if {[llength $tags] > 5} {
	    set max 5
	} else {
	    set max [llength $tags]
	}
	for { set i 0 } { $i < $max } { incr i } {
	    if { $i < $max - 1 } {
		append command "[[lindex $tags $i] nodeValue], "
	    } else {
		append command "[[lindex $tags $i] nodeValue]."
	    }
	}
    } else {
	append command "no tags."
    }

    putserv "privmsg $chan :$command"


    
    return 0
}

proc pub_url { nick host hand chan arg } {
    url $nick $host $hand $chan $arg
}

proc msg_url { nick host hand arg } {
    global last
    set args [split $arg]
    if { [llength $args] == 0 || [string match "help" [lindex $args 0]] } {
	putserv "privmsg $nick :pm syntax: $last(char)url #channel"
    } elseif { [llength $args] == 1 } {
	url $nick $host $hand [lindex $args 0] ""
    }
}

proc url { nick host hand chan arg } {
    global last
    set arg [string trimright $arg]
    set args [split $arg]

    if { [llength $args] == 0 } {
	set target $nick
	putlog $target
    } elseif { [string match "help" [lindex $args 0]] } {
	putserv "privmsg $chan :syntax: !url <nick>.  If nick is ommitted, you are assumed to be the target."
    } elseif { [llength $args] == 1 } {
	set target [lindex $args 0]
    } else {
	putlog $arg
    }

    set lastnick [get_nick $target]
    
    putserv "privmsg $chan :http://last.fm/user/$lastnick"
}


    
proc pub_np { nick host hand chan arg } {
    np $nick $host $hand $chan $arg
}

proc msg_np { nick host hand arg } {
    global last
    set args [split $arg]
    if { [llength $args] == 0 || [string match "help" [lindex $args 0]] } {
	putserv "privmsg $nick :pm syntax: $last(char)np #channel"
    } elseif { [llength $args] == 1 } {
	np $nick $host $hand [lindex $args 0] "" 
    } 
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

init_nicks
bind pub $last(who) $last(char)np pub_np 
bind msg $last(who) $last(char)np msg_np
bind pub $last(who) $last(char)register pub_register
bind msg $last(who) $last(char)register msg_register
bind msg $last(who) $last(char)list msg_list
bind pub $last(who) $last(char)compare compare
bind pub $last(who) $last(char)cp compare
bind pub $last(who) $last(char)reg pub_register
bind msg $last(who) $last(char)url msg_url
bind pub $last(who) $last(char)url pub_url