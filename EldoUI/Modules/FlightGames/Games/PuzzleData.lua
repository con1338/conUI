-- EldoUI Flight Games: the boards of Ley Lines and Caravan Jam.
-- Made by tools/gen_puzzle_levels.py, which checks each one with a
-- solver: every Ley Lines board has exactly one answer (every cell
-- filled, no line next to itself), and every Caravan Jam board can be
-- solved in the number of moves it carries. Do not edit by hand.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames

M.PuzzleData = {
	-- Ley Lines: { board, answer } by size; a letter is a pair of runes.
	ley = {
		[5] = {
			{ "AE.....CD...E.C.D..BAB...", "AECCCAECDCAEEDCADDDBABBBB" },
			{ "BD.E..C.....A...C.DE.B..A", "BDDEEBCDDEBCADEBCADEBBAAA" },
			{ "D..CBE.C......A.ED..B...A", "DDCCBEDCBBEDDBAEEDBABBBBA" },
			{ "DE..B..EBAC.DC......A....", "DEEBBDDEBACDDCACCCCAAAAAA" },
			{ "A....B..BAE.C..D.ED.....C", "AAAAABBBBAEECCCDEEDCDDDDC" },
			{ "..DC.DG.G.BFE....FEC.BA.A", "DDDCCDGGGCBFEECBFFECBBAAA" },
			{ "C..CFBE.E..DF..B..DAA....", "CCCCFBEEEFBDFFFBDDDAAAAAA" },
			{ "BC..E....DA......CE.ABD..", "BCCEEBBCEDABCEDABCEDABDDD" },
		},
		[6] = {
			{ "A....A.B...D.E.C..........E...B..CD.", "AAAAAABBEEEDBEECEDBCCCEDBCEEEDBCCCDD" },
			{ "AB......GD....BE.G..C..F....D.ACEF..", "ABGGGGABGDDGABBEDGACCEDFACEEDFACEFFF" },
			{ "........CEFG..E...G.D..FC..B.DB..A.A", "GGGGGGGCCEFGGCEEFFGCDDDFCCBBDDBBBAAA" },
			{ "DC..B..G..C..F..A......BDE....E.F.GA", "DCCCBBDGGCCBDFGGABDFFGABDEFGAAEEFGGA" },
			{ "BC..CD.F.....E.G....GF.DB....EA....A", "BCCCCDBFFFFDBEGGFDBEGFFDBEEEEEAAAAAA" },
			{ "A.C...B...F..G.FD.......BGE...E..ADC", "AACCCCBAAFFCBGAFDCBGAADCBGEADCEEEADC" },
			{ ".....A....CE...D..A..E.BC.DB..F....F", "AAAAAAACCCCEACDDEEACDEEBCCDBBBFFFFFF" },
			{ "....GA..BA....ED.DG..EFC..F...BC....", "GGGGGAGBBAAAGBEDDDGBEEFCBBFFFCBCCCCC" },
		},
		[7] = {
			{ "FG......E..ED...BC.....C.DA..B......A.G.........F", "FGGGGGGFEEEEDGFBBCDDGFBCCDAGFBAAAAGFAAGGGGFFFFFFF" },
			{ ".......BFG....A.....B.C.E....D.........EF.AD...CG", "BBBBBBBBFGGGGBAFFFFGBACCEFGGADCEFFGADCEEFGADCCCCG" },
			{ "GB.BC.....FED.A.F........G....E...........AD...C.", "GBBBCCCGGFFEDCAGFEEDCAGEEGDCAGEGGDCAGGGDDCADDDDCC" },
			{ "F.....A.AGCD........D....B.C..BE.........E....F.G", "FAAAAAAFAGCDDDFGGCCCDFGBBBCCFGBEEEEFGGGGGEFFFFFGG" },
			{ "..DB...DA...E...ECF........G..F........CB.AG.....", "DDDBBBBDAEEEEBAAECFBBACCCFBGACFFFBGACCCCBGAGGGGGG" },
			{ "....A...C..GB..BC...A............F..DF...DGE....E", "GGGGAAAGCCGGBAGBCBBBAGBBBDDDGDDDDFDGDFFFFDGEEEEEE" },
			{ "G.....BA.CE.....D.E......DC........F...AGB......F", "GGCCCCBAGCEECBAGDDECBAGGDDCBAAGGGGBFAAAAGBFFFFFFF" },
			{ "..........DFB..D......G....GEF..C.A..E.BC.A......", "GGGGGGGGDDDFBGGDFFFBGGGFBBBGEFFBCCAEEEBBCAAAAAAAA" },
		},
		[8] = {
			{ ".F..A......G..D...E................D.C........E..AF.B.C....BG...", "FFAAAGGGFAAGGGDGFAEDDDDGFAEDEEEGFAEDECEGFAEEECEGFAFBBCCGFFFBGGGG" },
			{ ".....G.ADE...D...........G..C...C.F.F...B.E............A.......B", "DDDDDGGADEEEDDGACCCEEEGACGCCCEGACGFFFEGABGEEEEGABGGGGGGABBBBBBBB" },
			{ "FDC............G.....B......E.A........E.........DF.G.B.......CA", "FDCGGGGGFDCGEEEGFDCGEBEEFDCGEBAEFDCGGBAEFDCCGBAAFDFCGBBAFFFCCCCA" },
			{ "A......D..E.........F..........G....EG.C.D.......F......AC..B..B", "ADDDDDDDADEGGGGGADEGFFFGADEGGGFGADEEEGFCADFFFFFCAFFCCCCCACCCBBBB" },
			{ ".......A..G.......F.....A....D......B.B..C....D.........E.C..EGF", "AAAAAAAAAGGFFFFFAGFFBBBFAGGGBDBFEEEGBDBFECEGGDDFECEEGGGFECCEEEGF" },
			{ "........GC...E.....D.C..AB......F.....G...B....F.A...DE.........", "GGGGGGGGGCCCCEEGAAADCCEGABADDEEGFBAADEGGFBBADEEFFAAADDEFFFFFFFFF" },
		},
	},
	-- Caravan Jam: { board, fewest moves }; x is the kodo cart.
	caravan = {
		easy = {
			{ "bb.....ccgg...xxed....ed.ffaa.hhh...", 5 },
			{ ".bbff.iiccd.xxh.da..h..a..eeeagg....", 7 },
			{ "ii.aa...hhhe.xx.jedd.cj.bb.cggkkkff.", 5 },
			{ ".lldjjii.dkkxx..bce.fhbcegfhb..gaaa.", 5 },
			{ ".b..h.ib..h.ixxajeif.ajecf.gg.c.dd..", 5 },
			{ ".g..ee.g.bd.xx.bda..c..a..c.fahh..f.", 5 },
			{ ".ddd..j.hh..jxxbic..abicg.affcg.a.ee", 7 },
			{ "a...hhadd.gfxx.igf...i.f..ee..bbb.cc", 5 },
		},
		normal = {
			{ "ggg.....a.iixxad..h.cdkkh.cffbeejj.b", 10 },
			{ "..dii.lldcgbfxxcgbf..e..kk.e.haaajjh", 10 },
			{ "gggfc....fcexxb..ej.b.iijhhaa.ddd...", 14 },
			{ ".iidjjkkhd..xxhdga..eegab.lll.bccff.", 11 },
			{ "..ee.....ha..xxha..bbba..dgccf.dg..f", 10 },
			{ ".gcckk.g.ejdxxaejd.fahh..f...i.bb..i", 10 },
			{ "fdccckfdahhkxxaj..b..jggb..eelb.ii.l", 10 },
			{ "..ggg..ffiib..xxlbaae.lbdjehh.djcckk", 12 },
		},
		hard = {
			{ "jbbkaajcck..xxfi....fiehggg.eh.llddd", 17 },
			{ "hhh......ce.xx.ceg.dbbeg.dfaa...f...", 17 },
			{ "fffj....gjccxxgdh.ikkdh.iee.a..bbba.", 18 },
			{ "chaiilchaf.lxx.fegbbk.eg..kde.jj.d..", 18 },
			{ "fffdb.e..dbje.xxcj..ahcj..ahiigg....", 23 },
			{ "..hha..fffa...xxg.bbc.g.eic.ddei....", 23 },
			{ ".jggg..jdddexxh.iec.hai.ckkalb.ffalb", 16 },
			{ "kggc..k..cibxxjhibffjh.deaa..de....d", 17 },
		},
	},
}
