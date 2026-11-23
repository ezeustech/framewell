# Original color palettes inspired by character clothing and motifs. No artwork or logos.
function Get-GamingThemes {
    $rows=@(
        @('Dark','Dark','Essentials','Slate surfaces and a clear blue accent.','#087CFA','#282F3A','#232A35','#202630','#B8C2D2','#263E5D','#3B475B','#82BEFF'),
        @('Light','Light','Essentials','Bright neutral surfaces.','#087CFA','#FFFFFF','#FAFBFD','#F0F2F6','#617087','#DDE8F7','#E1E5EC','#087CFA'),
        @('OLED','OLED','Essentials','Pure black surfaces with blue highlights.','#087CFA','#000000','#000000','#000000','#B9C2D0','#152C47','#303030','#82BEFF'),
        @('Midnight','Midnight','Essentials','Deep navy and cool blue.','#4379DC','#17253E','#111D32','#0B1629','#B4C7E4','#2C4570','#2C3E5C','#B5CFFF'),
        @('Jonathan','Jonathan Joestar','Joestars','Hamon blue with warm brass accents.','#306FC0','#172E48','#101F32','#0D1929','#B1C8E2','#254974','#354A64','#E8C788'),
        @('Joseph','Joseph Joestar','Joestars','Olive, scarf red and desert gold.','#A3464D','#292D21','#1D2119','#171B14','#D0D2BA','#4C3C2B','#484D3A','#EACB8A'),
        @('Jotaro','Jotaro Kujo','Joestars','Ink black, deep violet and a golden chain.','#8062B8','#242131','#171620','#101016','#C9C1D9','#39304F','#454052','#E7C36E'),
        @('Josuke','Josuke Higashikata','Joestars','School-uniform navy and heart pink.','#9E58BE','#25213F','#19172D','#121121','#CDC1E3','#44325F','#49405D','#F29CCF'),
        @('Giorno','Giorno Giovanna','Joestars','Golden resolve with orchid pink.','#B63F83','#342136','#241724','#1B111C','#E0BDD5','#5B2B50','#614158','#F0D17E'),
        @('Jolyne','Jolyne Cujoh','Joestars','Emerald threads and ocean blue.','#278F78','#17312D','#10231F','#0C1917','#B7D8C9','#245547','#34564B','#B9DF84'),
        @('Johnny','Johnny Joestar','Joestars','Starlight blue and soft rose.','#547DCA','#202C46','#172034','#101827','#C0CEE8','#334D77','#3F5270','#E6B7DE'),
        @('Gappy','Josuke / Gappy','Joestars','Sailor blue, cream and plum.','#7962B2','#26283C','#1A1C2C','#141521','#D1C8DB','#413B5D','#4D4961','#E5D6AC'),
        @('Jodio','Jodio Joestar','Joestars','Storm blue with lavender highlights.','#736BC6','#232941','#181C2E','#111522','#C6CAE4','#3F456A','#424D69','#C9B6F0'),
        @('DioBrando','Dio Brando','Main rivals','Victorian wine and amber.','#A85F31','#332621','#241A18','#1B1312','#D9C3B4','#593B2A','#5B4338','#EAC17D'),
        @('DIO','DIO','Main rivals','Gold, obsidian and emerald.','#A67924','#29251A','#1B1912','#11120D','#D9D0B4','#4C4123','#544D32','#F1CF68'),
        @('Kars','Kars','Main rivals','Amethyst, garnet and bronze.','#975FBC','#302039','#201626','#18101E','#D6BBDD','#4F315D','#594060','#E0B483'),
        @('Kira','Yoshikage Kira','Main rivals','Lavender tailoring and pale rose.','#866FC0','#2C293E','#1E1B2C','#161320','#CCC4DF','#49415F','#534A67','#E5B9D3'),
        @('Diavolo','Diavolo','Main rivals','Crimson, magenta and deep violet.','#BF426E','#341F30','#241521','#190F19','#DDBACF','#5C2C49','#603B53','#F29EB8'),
        @('Pucci','Enrico Pucci','Main rivals','Midnight violet and celestial gold.','#7F6AB0','#252437','#191824','#11111B','#CCC5D8','#413954','#4D465E','#DDC781'),
        @('FunnyValentine','Funny Valentine','Main rivals','Dusty rose, royal blue and ivory.','#A15B8E','#302638','#221B28','#18131E','#DBBFD5','#53374E','#594558','#E8D6BD'),
        @('Tooru','Tooru','Main rivals','Forest green, violet and autumn gold.','#75724C','#282B22','#1B1E18','#12160F','#CDD0BC','#454632','#4B5140','#C9ABD9'),
        @('DiegoBrando','Diego Brando','Main rivals','Teal racing silk and sandstone.','#328B91','#1D3035','#142126','#0E191D','#BFD6D9','#2E5158','#36565E','#E3CE8C'),
        @('AccaHowler','Acca Howler','Main rivals','Island green, dark brass and warm stone.','#82924F','#293126','#1C231A','#141A12','#CFD7BE','#485435','#515D43','#DDC69A'),
        @('Speedwagon','Robert E. O. Speedwagon','Allies','Warm copper and tailored charcoal.','#AA673D','#302825','#211D1A','#181512','#D9C6B9','#51392B','#56463A','#E7BE83'),
        @('Caesar','Caesar Zeppeli','Allies','Lime accents against warm violet.','#94854C','#2D2936','#201C27','#17131E','#D5C9DD','#4E4356','#584B60','#DCD894'),
        @('Kakyoin','Noriaki Kakyoin','Allies','Cherry red and dark emerald.','#B85364','#20312A','#16221D','#0F1914','#C2D8C9','#394A38','#42574A','#EFACB6'),
        @('Polnareff','Jean Pierre Polnareff','Allies','Silver steel and cobalt.','#637FB6','#29303C','#1C222B','#14191F','#CDD3DD','#3C4D66','#4D596C','#DAE1EF'),
        @('Rohan','Rohan Kishibe','Allies','Ink green and a pale mint nib.','#478B73','#20312C','#16221E','#101915','#BED8CA','#315145','#3E584C','#C1E3AD'),
        @('Bruno','Bruno Bucciarati','Allies','Pearl, cobalt and zipper gold.','#5E79B7','#252C3A','#1A202A','#12171F','#C6D1E2','#394C6B','#47576C','#E4CE91'),
        @('Mista','Guido Mista','Allies','Racing red and navy blue.','#B3484C','#2F2631','#211A24','#18131A','#D8C0D0','#52323F','#5A3F50','#EDBE85'),
        @('Trish','Trish Una','Allies','Rose coral and plum.','#BE5C8E','#342335','#251827','#1B111C','#E1C0DA','#5B3352','#64445C','#F0B6CD'),
        @('Weather','Weather Report','Allies','Cloud silver and blue-gray.','#6A8CA6','#26313A','#1B232A','#131A20','#CAD7E0','#3E5363','#4B606F','#D6E5EE'),
        @('Gyro','Gyro Zeppeli','Allies','Sage steel and violet.','#7C7D48','#2D2E25','#202019','#171812','#D1D0BA','#4D4833','#55553E','#D4B8E7')
    )
    foreach($r in $rows){[pscustomobject]@{Id=$r[0];Name=$r[1];Group=$r[2];Description=$r[3];Accent=$r[4];Surface=$r[5];Background=$r[6];Sidebar=$r[7];Secondary=$r[8];Selection=$r[9];Border=$r[10];Metric=$r[11]}}
}
