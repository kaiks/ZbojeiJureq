# az plugin

az plugin manages the az irc game. A word from a dictionary is randomly chosen, and players are supposed to guess the word.


## Commands
### .az
starts a new az game

### .az ez
starts a new easy az game with the word drawn from limited vocabulary

### .az top [n]
shows the top n player stats. n is optional

### .az stop
ends the game

### .az hint
presents a hint.
hints are available after 10 tries

## Scores
The winning score for a non-ez game is calculated as follows:
`(100*exp(-(n-1)**2/50**2)).ceil + p`
where:
* n is the number of total tries within the game
* p is the number of players that guessed any word during the game

ez game scores are divided by 2

# Note plugin

Note plugin lets you leave messages for others for when they come back.


## Commands
### .note nick message
leaves a *message* for *nick*

### .mynotes
displays the notes that you have left for other people

# Timer plugin

Timer plugin lets you send messages into the future.


## Commands
### .timer [xx.xx] [d|h|m|s] message
leaves a message that will be sent in xx.xx days/hours/minutes/seconds
######Examples:
- *.timer 15.50 m hello*
will send the message *hello* after 15minutes and 30 seconds
- *.timer 20.50 d hello*
will send the message *hello* after 20days and 12 hours

### .timer [hh:mm] message
leaves a message that will be sent at hh:mm, where hh-hours, mm-minutes
Examples:
- *.timer 15:50 hello*
will send the message *hello* at 15:50
- *.timer 15:50 hello* **when it's 16:30**
will send the message *hello* at 15:50 the following day.

### .timer [dd.mm.yyyy] [hh:mm] message
leaves a message on the date dd.mm.yyyy at hh:mm.
Examples:
- *.timer 30.12.2020 23:20 hello*
will send the message *hello* at 23:20 on 30.12.2020

# Uno plugin

Uno plugin manages the Uno irc game.


## Commands
### .uno
creates a new uno game

### .uno casual
starts a new unranked game

### .uno stop
closes an existing uno game

### .uno top [n]
shows the top n player stats. n is optional

### .deal
deals cards to players and starts the game



## In-game commands

### ca
shows you your cards

### ca
shows you your cards

### od
presents current player order

### pe
picks a card from the card pile

### pa
passes the turn

### pl [card]
plays a card from your hand, e.g. pl y6

cards can be wild or normal, where
normal cards are formatted as [color][figure], where
color	= [r,g,b,y]
figure	= [0,1,2,3,4,5,6,7,8,9,R,S,+2]

wild cards are formatted as [figure][color], where
figure	= [wd4,w]
