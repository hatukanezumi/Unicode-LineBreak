=encoding utf8

This file is automatically generated.  DON'T EDIT THIS FILE MANUALLY.

=cut

package Unicode::LineBreak;

use constant { M => 4, D => 3, I => 2, P => 1,};

use constant {
    LB_BK => 0,
    LB_CR => 1,
    LB_LF => 2,
    LB_NL => 3,
    LB_SP => 4,
    LB_OP => 5,
    LB_CL => 6,
    LB_QU => 7,
    LB_GL => 8,
    LB_NS => 9,
    LB_EX => 10,
    LB_SY => 11,
    LB_IS => 12,
    LB_PR => 13,
    LB_PO => 14,
    LB_NU => 15,
    LB_AL => 16,
    LB_ID => 17,
    LB_IN => 18,
    LB_HY => 19,
    LB_BA => 20,
    LB_BB => 21,
    LB_B2 => 22,
    LB_CB => 23,
    LB_ZW => 24,
    LB_CM => 25,
    LB_WJ => 26,
    LB_H2 => 27,
    LB_H3 => 28,
    LB_JL => 29,
    LB_JV => 30,
    LB_JT => 31,
    LB_SG => 32,
    LB_AI => 33,
    LB_SA => 34,
    LB_XX => 35,
    LB_SAbase => 36,
    LB_SAextend => 37,
    LB_SAprepend => 38,
};

use constant {
    IDEOGRAPHIC_ITERATION_MARKS => [0x3005, 0x303B, 0x309D, 0x309E, 0x30FD, 0x30FE, ],
    KANA_NONSTARTERS => [0x3005, 0x303B, 0x303C, 0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E, 0x3095, 0x3096, 0x309D, 0x309E, 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE, 0x30F5, 0x30F6, 0x30FC, 0x30FD, 0x30FE, 0x31F0, 0x31F1, 0x31F2, 0x31F3, 0x31F4, 0x31F5, 0x31F6, 0x31F7, 0x31F8, 0x31F9, 0x31FA, 0x31FB, 0x31FC, 0x31FD, 0x31FE, 0x31FF, 0xFF67, 0xFF68, 0xFF69, 0xFF6A, 0xFF6B, 0xFF6C, 0xFF6D, 0xFF6E, 0xFF6F, 0xFF70, ],
    KANA_PROLONGED_SOUND_MARKS => [0x30FC, 0xFF70, ],
    KANA_SMALL_LETTERS => [0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E, 0x3095, 0x3096, 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE, 0x30F5, 0x30F6, 0x31F0, 0x31F1, 0x31F2, 0x31F3, 0x31F4, 0x31F5, 0x31F6, 0x31F7, 0x31F8, 0x31F9, 0x31FA, 0x31FB, 0x31FC, 0x31FD, 0x31FE, 0x31FF, 0xFF67, 0xFF68, 0xFF69, 0xFF6A, 0xFF6B, 0xFF6C, 0xFF6D, 0xFF6E, 0xFF6F, ],
    MASU_MARK => [0x303C, ],
};

use constant {
    EA_Z => 0,
    EA_Na => 1,
    EA_N => 2,
    EA_A => 3,
    EA_W => 4,
    EA_H => 5,
    EA_F => 6,
};

use constant {
    AMBIGUOUS_ALPHABETICS => [0x00C6, 0x00D0, 0x00D8, 0x00DE, 0x00DF, 0x00E0, 0x00E1, 0x00E6, 0x00E8, 0x00E9, 0x00EA, 0x00EC, 0x00ED, 0x00F0, 0x00F2, 0x00F3, 0x00F8, 0x00F9, 0x00FA, 0x00FC, 0x00FE, 0x0101, 0x0111, 0x0113, 0x011B, 0x0126, 0x0127, 0x012B, 0x0131, 0x0132, 0x0133, 0x0138, 0x013F, 0x0140, 0x0141, 0x0142, 0x0144, 0x0148, 0x0149, 0x014A, 0x014B, 0x014D, 0x0152, 0x0153, 0x0166, 0x0167, 0x016B, 0x01CE, 0x01D0, 0x01D2, 0x01D4, 0x01D6, 0x01D8, 0x01DA, 0x01DC, 0x0251, 0x0261, 0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397, 0x0398, 0x0399, 0x039A, 0x039B, 0x039C, 0x039D, 0x039E, 0x039F, 0x03A0, 0x03A1, 0x03A3, 0x03A4, 0x03A5, 0x03A6, 0x03A7, 0x03A8, 0x03A9, 0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5, 0x03B6, 0x03B7, 0x03B8, 0x03B9, 0x03BA, 0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF, 0x03C0, 0x03C1, 0x03C3, 0x03C4, 0x03C5, 0x03C6, 0x03C7, 0x03C8, 0x03C9, 0x0401, 0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F, 0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427, 0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F, 0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F, 0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447, 0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F, 0x0451, ],
    AMBIGUOUS_CYRILLIC => [0x0401, 0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F, 0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427, 0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F, 0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F, 0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447, 0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F, 0x0451, ],
    AMBIGUOUS_GREEK => [0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397, 0x0398, 0x0399, 0x039A, 0x039B, 0x039C, 0x039D, 0x039E, 0x039F, 0x03A0, 0x03A1, 0x03A3, 0x03A4, 0x03A5, 0x03A6, 0x03A7, 0x03A8, 0x03A9, 0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5, 0x03B6, 0x03B7, 0x03B8, 0x03B9, 0x03BA, 0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF, 0x03C0, 0x03C1, 0x03C3, 0x03C4, 0x03C5, 0x03C6, 0x03C7, 0x03C8, 0x03C9, ],
    AMBIGUOUS_LATIN => [0x00C6, 0x00D0, 0x00D8, 0x00DE, 0x00DF, 0x00E0, 0x00E1, 0x00E6, 0x00E8, 0x00E9, 0x00EA, 0x00EC, 0x00ED, 0x00F0, 0x00F2, 0x00F3, 0x00F8, 0x00F9, 0x00FA, 0x00FC, 0x00FE, 0x0101, 0x0111, 0x0113, 0x011B, 0x0126, 0x0127, 0x012B, 0x0131, 0x0132, 0x0133, 0x0138, 0x013F, 0x0140, 0x0141, 0x0142, 0x0144, 0x0148, 0x0149, 0x014A, 0x014B, 0x014D, 0x0152, 0x0153, 0x0166, 0x0167, 0x016B, 0x01CE, 0x01D0, 0x01D2, 0x01D4, 0x01D6, 0x01D8, 0x01DA, 0x01DC, 0x0251, 0x0261, ],
    QUESTIONABLE_NARROW_SIGNS => [0x00A2, 0x00A3, 0x00A5, 0x00A6, 0x00AC, 0x00AF, ],
};

use constant {
    SCRIPT_Common => 0,
    SCRIPT_Inherited => 1,
    SCRIPT_Unknown => 2,
    SCRIPT_Thai => 3,
    SCRIPT_Lao => 4,
    SCRIPT_Myanmar => 5,
    SCRIPT_Khmer => 6,
    SCRIPT_Tai_Le => 7,
    SCRIPT_New_Tai_Lue => 8,
};

1;
