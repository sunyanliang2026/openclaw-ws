import re


def split_sentences(text: str):
    parts = re.split(r'[。！？!?\n]', text)
    return [p.strip() for p in parts if p.strip()]


def analyze_text(content: str):
    sentences = split_sentences(content)
    text_length = len(content)
    sentence_count = len(sentences)

    sentence_lengths = [len(s) for s in sentences] if sentences else [0]
    avg_sentence_length = sum(sentence_lengths) / max(sentence_count, 1)
    unique_sentences = len(set(sentences))

    repeat_ratio = 0
    if sentence_count > 0:
        repeat_ratio = 1 - unique_sentences / sentence_count

    template_phrases = ["首先", "其次", "最后", "总之", "综上所述", "可以看出"]
    template_hits = sum(1 for phrase in template_phrases if phrase in content)

    has_source_hint = any(keyword in content for keyword in ["来源", "据报道", "记者", "发布时间", "链接"])

    points = []
    risk_score = 0

    if repeat_ratio > 0.3:
        points.append("句式结构重复度较高")
        risk_score += 25

    if template_hits >= 3:
        points.append("存在较明显的模板化表达")
        risk_score += 20

    if avg_sentence_length > 35:
        points.append("句子长度偏长，表达可能较为模式化")
        risk_score += 10

    if not has_source_hint:
        points.append("文本缺少明确来源支撑")
        risk_score += 15

    if sentence_count <= 2 and text_length > 80:
        points.append("段落结构较单一")
        risk_score += 10

    if risk_score < 40:
        risk_level = "low"
    elif risk_score < 70:
        risk_level = "medium"
    else:
        risk_level = "high"

    if not points:
        points.append("当前未发现明显异常特征")

    return {
        "success": True,
        "type": "text",
        "risk_level": risk_level,
        "score": risk_score,
        "points": points,
        "details": {
            "length": text_length,
            "sentence_count": sentence_count,
            "repeat_ratio": round(repeat_ratio, 2),
            "template_hits": template_hits,
            "avg_sentence_length": round(avg_sentence_length, 2),
            "has_source_hint": has_source_hint
        },
        "message": "文本分析完成"
    }
