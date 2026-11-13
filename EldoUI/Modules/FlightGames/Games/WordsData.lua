-- EldoUI Flight Games: the word lists of Daily Word, written from scratch
-- for EldoUI: common five-letter words in US English and in Danish. Each
-- day picks one word per language; free play picks any of them.
local _, E = ...
local M = E.FlightGames

M.WordsData = {
	en = (
		"about above actor acute adapt admit adopt adult after again agent agree ahead alarm album alert " ..
		"alike alive allow alone along alter amber among angel anger angle angry ankle apart apple apply " ..
		"arena argue arise armor array arrow aside asset avoid awake award aware awful bacon badge baker " ..
		"basic basin batch beach beard beast begin below bench berry birth black blade blame blank blast " ..
		"blaze bleak blend bless blind block blood bloom blown board boast bonus boost booth bound brain " ..
		"brake brand brass brave bread break breed brick bride brief bring broad broke brook broom brown " ..
		"brush build built bunch burst cabin cable camel canal candy canoe cargo carry carve catch cause " ..
		"cedar chain chair chalk charm chart chase cheap check cheek cheer chess chest chief child chill " ..
		"choir chord chose cider civil claim clash class clean clear clerk click cliff climb cloak clock " ..
		"close cloth cloud clown coach coast cobra coral couch cough count court cover crack craft crane " ..
		"crash crawl cream creek crest crime crisp crowd crown crude cruel crumb crush crust cubic curve " ..
		"cycle daily dairy dance death debut decay delay delta dense depth devil diary dirty ditch dizzy " ..
		"dodge doubt dough dozen draft drain drake drama drank drawn dread dream dress dried drift drill " ..
		"drink drive drove drown dryad dwarf dwell eager eagle early earth easel eaten ebony eight elbow " ..
		"elder elect elite elven ember empty enemy enjoy enter entry equal error essay event every exact " ..
		"exile exist extra fable faint fairy faith false fancy feast fence ferry fever fiber field fiery " ..
		"fifth fifty fight final flail flame flank flash flask fleet flesh flint float flock flood floor " ..
		"flour fluid flute focus foggy force forge forth forty forum found frame fresh front frost froze " ..
		"fruit fully funny gauge ghost giant given glade glare glass gleam glide globe gloom glory glove " ..
		"gnome goose grace grade grain grand grant grape grasp grass grave gravy great greed green greet " ..
		"grief grill grind groan group grove growl grown guard guess guest guide guild habit happy harsh " ..
		"haste hatch haunt haven heart heavy hedge hello hence heron hobby honey honor horse hotel hound " ..
		"house human humid humor hurry ideal image index inner input issue ivory jelly jewel joint joker " ..
		"judge juice jumpy karma kayak knack kneel knife knock known label labor lance large laser later " ..
		"laugh layer learn lease least leave ledge legal lemon level lever light lilac limit linen liver " ..
		"llama local lodge lofty logic loose lotus lover lower loyal lucky lunar lunch lying magic major " ..
		"maker manor maple march marsh match mayor meant medal melee melon mercy merit merry metal meter " ..
		"might minor mirth model moist money month moose moral motor mount mouse mouth movie muddy mural " ..
		"music naval nerve never newly night ninja noble noise north notch novel nurse nylon oasis occur " ..
		"ocean offer often olive onion opera orbit order organ other otter ounce outer owner paint panel " ..
		"panic paper parch party paste patch pause peace peach pearl pedal penny perch peril phase phone " ..
		"photo piano piece pilot pinch pious pitch pixel pizza place plain plane plant plate plaza plead " ..
		"pluck plumb plume plush point poise polar porch pouch pound power press price pride prime print " ..
		"prior prism prize probe prone proof proud prove prowl prune pulse punch pupil puppy purse quail " ..
		"quake queen query quest quick quiet quill quilt quirk quite quota quote radar radio rally ranch " ..
		"range rapid raven reach react ready realm rebel refer reign relax relay relic renew reply rider " ..
		"ridge rifle right rigid rival river roast robin robot rocky rogue roost rough round route royal " ..
		"ruins ruler rural rusty sadly saint salad salty sandy sauce scale scare scarf scene scent scoop " ..
		"scope score scout scrap screw sense serve seven shade shaft shake shame shape share shark sharp " ..
		"shear sheep sheet shelf shell shift shine shiny shire shirt shock shore short shout shrub siege " ..
		"sight silly since siren skill skull slate sleek sleep slept slice slide slime slope sloth small " ..
		"smart smell smile smith smoke snack snail snake snare sneak snowy sober solar solid solve sound " ..
		"south space spade spare spark spawn speak spear speed spell spend spent spice spicy spike spine " ..
		"spire spoke spoon sport spout spray squad squid stack staff stage stain stair stake stale stamp " ..
		"stand stare stark start state steak steal steam steel steep steer stern stick stiff still sting " ..
		"stock stone stood stool storm story stout stove straw stray strip stuck study stuff stump style " ..
		"sugar suite sunny super surge swamp swarm swear sweat sweep sweet swept swift swing sword swore " ..
		"sworn table tango taste teach teeth tempo thank theft theme thick thief thing think third thorn " ..
		"three threw throw thumb tidal tiger tight timer tired title toast today token tooth topaz torch " ..
		"total totem touch tough tower trace track trade trail train trait treat trend trial tribe trick " ..
		"tried troll troop trout truce truck truly trunk trust truth tulip twice twist ultra uncle under " ..
		"union unite unity until upper upset urban usage usual valid valor value vault venom verse vigor " ..
		"villa vinyl viola viper virus visit vital vivid vocal voice voter wagon waist waste watch water " ..
		"weave wedge weird whale wheat wheel where while whirl white whole widow width wield windy witch " ..
		"woken woman world worry worse worst worth wound woven wrath wreck wrist write wrong wrote yacht " ..
		"yearn yeast yield young youth zebra zesty"
	),
	da = (
		"abort agent aksel aktie alarm album alder alter andel anden andre angst ankel anker ansat april " ..
		"arena armen arter atlas avler bager bakke balje banan bande barre basar basis bedre bedst begge " ..
		"bejle bevis biler binde bjerg blade blank blege blind blink blive bluse blæse blæst bolig bonde " ..
		"borde brand brede brise brist brite broen brugt bruse brøde brøle bunke burde butik bygge bælte " ..
		"bævre bøger bølge cykel dagen dalen damen damer dampe danse dansk datid debat delta denne dette " ..
		"digte disse dolke drage drama dreng drift drink druer drøne dufte dukke dunke dvæle dværg dybde " ..
		"dyden dyner dynge dåsen dække egern egnet eksil emner enden enkel enorm ensom etage evige fabel " ..
		"facon fakta falde fange farve faste fatte feber fejle fejre femte fersk fiber figur filme finde " ..
		"fiske fjeld fjern fjols flade flage flirt flise flora flyve flåde fløde fløjl folde forbi forme " ..
		"forår fotos frisk fryse frøen frøer fugle fulde fuldt fyret fyrre fælde færge fødte følge først " ..
		"gabet galde galge gamle gange garde gaven gavne gemme genre gifte gilde glade glans glemt glide " ..
		"glose glæde gløde grave grene grime grise grove grube grund grøde grøft gulve gumme gynge gæste " ..
		"gøgle haler haven havet havre hegne hekse helst hende hente heste hilse hinde hjelm hjort hjælp " ..
		"holde hoppe horde hotel huske hvalp hvede hvide hvile hyrde hytte hårde hædre hælde hænge hæren " ..
		"hævne hørte igler indre irske jagte jakke jamre jorde jubel juice jævne kabel kaffe kager kalde " ..
		"kamel kampe kanal kande kanon kappe karse kaste katte kerne kigge kilde kiste kjole klage klang " ..
		"klare klemt klima klint kloak klode klogt klæbe knage knald knibe knive knude kokke kolde komet " ..
		"komme konge korps kraft krage krans krone kugle kulde kunne kunst kurve kvast kævle lager lampe " ..
		"lande lange larve laser leder lempe lever lidet liget lilla linde linje liste lodde lomme lotus " ..
		"lunde lunte lykke lyset længe lærke læser løber løgne løven mager magre malet manke marts maske " ..
		"masse megen melon messe meter midte minut moden modig molbo morse mosen motor musik myter måler " ..
		"månen mødre mørke nakke natur nedre negle nisse noder norne nævne nøgen nøgle odder ofret oktav " ..
		"olive onkel opera orden orgel ovale padde pakke palme panik papir parre parti pasta peber pigen " ..
		"pilen pilot pinde pirat plade plane plast pleje plove plump poesi pokal posen prins prise prøve " ..
		"puder pudse pulje pumpe pynte pæren pølse rabat racer radio rakte rampe rasle ravne regel regne " ..
		"rejse rende reven rimer rimet risen rodet roser rotte rumle runde ruste ryste række rødme sagde " ..
		"sagen salat salme salte samle sande sauna savne scene sejle sejre senge sidde sidst sikre silke " ..
		"sinde skabe skade skaft skakt skala skarp skibe skind skole skove skrig skrue skudt skule skyer " ..
		"skære skøre slags slank slave slibe slugt slæde smede smile smukt smøre snart snavs sneen snegl " ..
		"snyde sokke solen sorte sovne spade spand spejl spids spild spire spise spøge stald stand stang " ..
		"start stave stavn stede stege stejl stige stime stjal stole storm straf strøm stuen stump styre " ..
		"stærk støbe sukke sulte summe svamp svane svare svede sværd svært synge tabel tante tavle telte " ..
		"tiger timer tinde titel tjære tolke tomat tosse trane trave trold trone tryne træde trøst tunge " ..
		"tvivl tårne tænde tæppe tørre tøsen uglen ulven under unger union vakle valse vande vante varme " ..
		"vaske vejen vejre vende vifte vilje vinde vinge virke vogne vokse vrede vågen vække værdi værft " ..
		"værre åbent ånden ånder åndet åsted ægget ærter ødsle øksen økser ørken ørred østen"
	),
}
