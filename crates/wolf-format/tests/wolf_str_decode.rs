//! Regression tests for the CP932/GBK boundary in `decode_wolf_str`.
//!
//! The Chinese fan translation rewrote some display strings in GBK while the
//! original template text stayed CP932. A CP932 string whose halfwidth katakana
//! and kanji bytes happen to pair into valid GBK-extension characters used to be
//! decoded as GBK (rare hanzi), which also broke DB label matching downstream
//! (the save-slot level term resolved to the item term). These pin both sides of
//! the boundary: genuine CP932 (with halfwidth katakana) must stay CP932, and
//! genuine GBK Chinese must stay GBK.

use wolf_format::bytes::decode_wolf_str;

fn hex(s: &str) -> Vec<u8> {
    let mut out = Vec::new();
    let mut chars = s.chars();
    while let (Some(a), Some(b)) = (chars.next(), chars.next()) {
        let hi = a.to_digit(16).expect("hex");
        let lo = b.to_digit(16).expect("hex");
        out.push((hi * 16 + lo) as u8);
    }
    out
}

#[test]
fn cp932_halfwidth_kana_label_stays_japanese() {
    // "[ｽﾃｰﾀｽ]レベル" — the save-slot level term label (op250 pc395).
    let bytes = hex("5bbdc3b0c0bd5d838c8378838b");
    assert_eq!(decode_wolf_str(&bytes), "[ｽﾃｰﾀｽ]レベル");
}

#[test]
fn cp932_template_label_with_halfwidth_system_word() {
    // "基本ｼｽﾃﾑ用変数" — CDataBase 18 label used by 652 op250 sites.
    let bytes = hex("8aee967bbcbdc3d1977095cf9094");
    assert_eq!(decode_wolf_str(&bytes), "基本ｼｽﾃﾑ用変数");
}

#[test]
fn cp932_windowing_term_stays_japanese() {
    // "万能ｳｨﾝﾄﾞｳ" — variable DB window table name.
    let bytes = hex("969c945cb3a8ddc4deb3");
    assert_eq!(decode_wolf_str(&bytes), "万能ｳｨﾝﾄﾞｳ");
}

#[test]
fn genuine_gbk_chinese_is_not_reinterpreted_as_cp932() {
    // "选择要保存的数据。 " — a real GBK translation of a DataBase term.
    let bytes = hex("d1a1d4f1d2aab1a3b4e6b5c4cafdbedda1a320");
    assert_eq!(decode_wolf_str(&bytes), "选择要保存的数据。 ");

    let bytes = hex("c3bbd3d0cafdbedd"); // "没有数据"
    assert_eq!(decode_wolf_str(&bytes), "没有数据");
}

#[test]
fn gbk_chinese_ending_in_an_ellipsis_is_not_read_as_cp932() {
    // "\E欸…哥、哥哥…！？" — common event 295 pc53. The fan translation writes
    // the ellipsis as `A1 AD` and the fullwidth question mark as `A3 BF`, and
    // CP932 reads those leads as the halfwidth punctuation ｡ ｣, so the line
    // used to come out as halfwidth-kana noise.
    let bytes = hex("5c459a47a1adb8e7a1a2b8e7b8e7a1ada3a1a3bf");
    assert_eq!(decode_wolf_str(&bytes), "\\E欸…哥、哥哥…！？");
}

#[test]
fn gbk_chinese_full_of_question_marks_is_not_read_as_cp932() {
    // "\E欸…？哥…哥…？我…为什么…？" — SampleMapA event 17 pc388.
    let bytes = hex("5c459a47a1ada3bfb8e7a1adb8e7a1ada3bfced2a1adceaacab2c3b4a1ada3bf");
    assert_eq!(decode_wolf_str(&bytes), "\\E欸…？哥…哥…？我…为什么…？");
}

#[test]
fn gbk_japanese_left_behind_by_the_translation_is_read_as_gbk() {
    // "以下フェラ処理です" — this line stayed in the original encoding, and the
    // halfwidth punctuation it contains used to turn it into kana noise.
    let bytes = hex("d2d4cfc2a5d5a5a7a5e98449c0eda4c7a4b9");
    assert_eq!(decode_wolf_str(&bytes), "以下フェラ処理です");
}

#[test]
fn a_cp932_label_with_a_halfwidth_middle_dot_stays_cp932() {
    // "顔画像 [ﾊﾞﾄﾙ･ｽﾃｰﾀｽ用]" — the op250 label for the battle face graphic.
    // Its middle dot is U+FF65, one code point above the veto range, so the
    // label keeps pointing at the same database column.
    let bytes = hex("8ae789e6919c205bcadec4d9a5bdc3b0c0bd97705d");
    assert_eq!(decode_wolf_str(&bytes), "顔画像 [ﾊﾞﾄﾙ･ｽﾃｰﾀｽ用]");
}
