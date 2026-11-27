/// The tester's stress data for PR 2's layouts. A character that would be
/// invisible in the source (the family emoji's joiners) is built from its
/// code point.
library;

/// 80 characters: the note's limit.
const note80 =
    'Lunch with the team after a long meeting, then coffee and a slice of carrot cake';

/// 24 characters as people count them, 32 UTF-16 units.
final noteEmoji =
    'Coffee ${String.fromCharCode(0x2615)} with friends '
    '${String.fromCharCodes([0x1F389, 0x1F469, 0x200D, 0x1F469, 0x200D, 0x1F467])}';

/// Thai: no spaces between words (it breaks by dictionary).
const noteThai = 'ข้าวมันไก่กับน้ำส้มคั้นสดที่ร้านใกล้บ้าน';

/// 40 characters: the goal name's limit.
const goal40 = 'A new bike for long summer rides outside';

/// The 12-digit maximum, in minor units ($9,999,999,999.99).
const amountMax = 999999999999;

/// The longest of the nine category labels.
const longestCategory = 'Fun & going out';
