// Derelict Station - Metra Narrative adventure (Ink)
// Use non-bracket choices so # move: tags attach to Choice.tags (not inner content).
// Metra-visible runtime tags: # move:<id> on choices, # terminal:success|fail on endings

VAR has_keycard = false
VAR archive_found = false
VAR pirates_alerted = false
VAR ship_hull = 100

-> station_dock

=== station_dock ===
{ archive_found && !pirates_alerted:
    The dock is quiet. The archive sits secured in your pack. Your ship waits with hull integrity at {ship_hull}.
- else:
    { archive_found && pirates_alerted:
        Alarms echo through the dock. The archive is yours, but the band is hot. Hull at {ship_hull}.
    - else:
        You stand on the dock of an abandoned research station. Emergency strips cast a thin red wash. The corridor ahead is dark. Somewhere deeper, a sealed archive waits.
    }
}

* Enter the dark corridor # move:enter_corridor
    -> station_corridor
* { not archive_found } Abandon the archive and flee # move:abandon_mission
    You leave empty-handed. The station shrinks behind you. # terminal:fail
    -> END
* { archive_found && not pirates_alerted } Cast off and leave with the archive # move:escape_success
    You cast off clean - archive aboard, hull whole. Deep space opens ahead. # terminal:success
    -> END
* { archive_found && pirates_alerted } Limp away with the archive # move:limp_home
    You shove off under fire. The archive holds. Hull limps at {ship_hull}, but you clear the station. # terminal:success
    -> END

=== station_corridor ===
The corridor smells of coolant and dust. Crew lockers line one wall. A sealed hatch leads toward the archive wing.
{ has_keycard:
    A keycard warms in your hand.
}

* { not has_keycard } Search crew lockers # move:search_lockers
    ~ has_keycard = true
    You pry open a locker and find a faded keycard still encoded for archive access.
    -> station_corridor
* { not has_keycard } Force the sealed hatch # move:trip_alarm
    ~ pirates_alerted = true
    ~ ship_hull = 82
    The hatch screams as you force it. Somewhere outside, a pirate channel lights up.
    -> archive_room_hot
* { has_keycard && not archive_found } Use the keycard on the archive door # move:open_archive
    The keycard takes. The door seals behind you.
    -> archive_room_quiet

=== archive_room_quiet ===
~ archive_found = true
Racks of research cores fill the room. The station stays quiet - no alarm.

* Recover the archive quietly # move:grab_archive_quiet
    You take the cores and slip back toward the dock.
    -> station_dock

=== archive_room_hot ===
Alarms pulse. The archive is still sealed ahead of you; pirate chatter climbs the band. Hull reports {ship_hull}.

* Grab the archive under fire # move:grab_archive_hot
    ~ archive_found = true
    ~ ship_hull = 70
    You wrench the cores free as the corridor fills with noise.
    -> archive_room_escape

=== archive_room_escape ===
The archive is in your pack. The way back to the dock is no longer quiet. Hull at {ship_hull}.

* Run the gauntlet to the ship # move:escape_damaged
    ~ ship_hull = 40
    You sprint under fire and slam onto the dock, archive intact, hull smoking.
    -> station_dock
