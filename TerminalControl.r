#include <Carbon/Carbon.r>

#define Reserved8   reserved, reserved, reserved, reserved, reserved, reserved, reserved, reserved
#define Reserved12  Reserved8, reserved, reserved, reserved, reserved
#define Reserved13  Reserved12, reserved
#define dp_none__   noParams, "", directParamOptional, singleItem, notEnumerated, Reserved13
#define reply_none__   noReply, "", replyOptional, singleItem, notEnumerated, Reserved13
#define synonym_verb__ reply_none__, dp_none__, { }
#define plural__    "", {"", kAESpecialClassProperties, cType, "", reserved, singleItem, notEnumerated, readOnly, Reserved8, noApostrophe, notFeminine, notMasculine, plural}, {}

resource 'aete' (0, "TerminalControl Terminology") {
	0x1,  // major version
	0x0,  // minor version
	english,
	roman,
	{
		"TerminalControl Suite",
		"Control Terminal.app",
		'TTpl',
		1,
		1,
		{
			/* Events */

			"apply title",
			"Apply title to a terminal specified with TTY",
			'TTpl', 'aplT',
			'bool',
			"true if successed to activate specified process.",
			replyRequired, singleItem, notEnumerated, Reserved13,
			'TEXT',
			"title of terminal",
			directParamRequired,
			singleItem, notEnumerated, Reserved13,
			{
				"for tty", 'fTTY', 'TEXT',
				"device name",
				required,
				singleItem, notEnumerated, Reserved13
			},

			"title for tty",
			"get current custom for a terminal specifeid with TTY",
			'TTpl', 'getT',
			'TEXT',
			"custom title of a terminal",
			replyRequired, singleItem, notEnumerated, Reserved13,
			'TEXT',
			"TTY name",
			directParamRequired,
			singleItem, notEnumerated, Reserved13,
			{

			}
		},
		{
			/* Classes */

		},
		{
			/* Comparisons */
		},
		{
			/* Enumerations */
		}
	}
};
