#! /usr/bin/env perl6

use v6;

my constant $no_room_default = 'Pas de salle';

# Event class
class Event {
    has Str $.title is rw = '?';
    has DateTime $.start is rw;
    has DateTime $.end is rw;
    has Str $.room is rw = $no_room_default;
    has Str $.groups is rw = '';
    has Str $.notes is rw = '';
    has Str $.category is rw = '';

    method to_ical_VEVENT {
        # This is where to tweak if you want a different output !
        my $dtstart = $.date_to_ical_time($.start);
        my $dtend = $.date_to_ical_time($.end);
        join "\n",
            "BEGIN:VEVENT",
            "DTSTART:$dtstart",
            "DTEND:$dtend",
            "SUMMARY:$.title",
            "CATEGORIES:$.category",
            "LOCATION:$.room",
            "DESCRIPTION:Groupes:\\n$.groups\\nNotes:\\n$.notes",
            "END:VEVENT";
    }

    method date_to_ical_time(DateTime $dt) {
        sprintf "%d%02d%02dT%02d%02d%02dZ",
            $dt.year, $dt.month, $dt.day, $dt.hour, $dt.minute, $dt.second;
    }
}

sub week_index(Str $yesnochain) {
    my $wk = index($yesnochain, 'Y');
    if $wk < 20 {
        34 + $wk;
    } else {
        $wk - 19;
    }
}

sub date_from_year_and_week($year, $week) {
    # Variant of https://stackoverflow.com/questions/9423087/perl-given-the-year-and-week-number-how-can-i-get-the-first-date-in-that-week.
    # If there is actually a good reason to set the 4th instead of the 1st, mail me :)
    DateTime
        .new(year => $year, month => 1, day => 1, timezone => $*TZ)
        .later(weeks => $week)
        .truncated-to('week');
}

grammar CelcatEventsGrammar {
    token TOP           { [ \v || <EVENT> ]* .* }
    token EVENT         { '<event' <text> '>' [ \v || <NODE> ]* '</event>' }
    token NODE          { <rawweek> || <starttime> || <endtime> || <day> ||
                          <category> || <resources> || <notes> || <useless> }

    token rawweek       { '<rawweeks>' <yesnochain> '</rawweeks>' }
    token yesnochain    { 'N'* 'Y' 'N'* }

    token starttime     { '<starttime>' <hour> '</starttime>' }
    token endtime       { '<endtime>' <hour> '</endtime>' }
    token hour          { <num> ':' <num> }
    token num           { \d+ }

    token day           { '<day>' <dayindex> '</day>' }
    token dayindex      { <[0 .. 6]> }

    token category      { '<category>' <text> '</category>' }

    token notes         { '<notes>' .*? '</notes>' } # The ? makes the match non-greedy

    token resources     { '<resources>' [ \v || <RESOURCE> ]* '</resources>' }
    token RESOURCE      { <module> || <groups> || <room> }
    token module        { '<module' <text> '>' [ \v || <content> ]* '</module>' }
    token groups        { '<group' <text> '>' [ \v ||  <content> ]* '</group>' }
    token room          { '<room' <text> '>' [ \v ||  <content> ]* '</room>' }

    token content       { '<item>' <text> '</item>' }
    token useless       { '<pretty' \w* '>' .*? '</pretty' \w* '>' }
    token text          { <-[\<\>]>* }
    token quotedtext    { <-[\"]>* }  #" This comment prevents highlighters from going wild.
}


class CelcatActions {
    has Event @.events;
    has Event $!temp = Event.new;
    
    has Int $!week = 0;
    has Int $!day_in_week = 0;
    has UInt $!start_hh = 0;
    has UInt $!end_hh = 0;
    has UInt $!start_mm = 0;
    has UInt $!end_mm = 0;

    method EVENT($/) {
        $!temp.start = date_from_year_and_week(2017, $!week)
            .later(days => $!day_in_week)
            .later(hours => $!start_hh)
            .later(minute => $!start_mm)
            .utc;

        $!temp.end = date_from_year_and_week(2017, $!week)
            .later(days => $!day_in_week)
            .later(hours => $!end_hh)
            .later(minute => $!end_mm)
            .utc;
        
        say $!temp.to_ical_VEVENT;

        # Reset event.
        $!temp = Event.new;
    }

    method yesnochain($/) {
        $!week = week_index($/.Str);
    }

    method starttime($/) {
        $!start_hh = $/<hour><num>[0].Str.Int;
        $!start_mm = $/<hour><num>[1].Str.Int;
    }

    method endtime($/) {
        $!end_hh = $/<hour><num>[0].Str.Int;
        $!end_mm = $/<hour><num>[1].Str.Int;
    }

    method dayindex($/) {
        $!day_in_week = $/.Str.Int;
    }

    method room($/) {
        $!temp.room = $<content>[0]<text>.Str;
    }

    method module($/) {
        $!temp.title = $<content>[0]<text>.Str; # The syntax made my brain explode.
    }

    method category($/) {
        $!temp.category = $<text>.Str;
    }

    method groups($/) {
        for $<content> -> $grp {
            $!temp.groups ~= $grp<text>.Str ~ "\\n";
        }
    }

    method notes($/) {
        $!temp.notes = $/.Str;
    }

}

# Load file and remove <br>s
my $source = "sample.xml".IO.slurp;

# Extract data we want from the headers and cut them
my $
$source = substr($source, index($source, '<event '));

# And output to stdout
say "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:Perl 6 grammar";

my $actions = CelcatActions.new;
my $celcat = CelcatEventsGrammar.parse($source, :$actions);

say 'END:VCALENDAR';

