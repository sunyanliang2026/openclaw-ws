from PIL import Image, ExifTags
import cv2
import numpy as np


def get_exif_data(image_path: str):
    try:
        image = Image.open(image_path)
        exif = image.getexif()
        if not exif:
            return {}

        exif_data = {}
        for tag_id, value in exif.items():
            tag = ExifTags.TAGS.get(tag_id, tag_id)
            exif_data[str(tag)] = str(value)
        return exif_data
    except Exception:
        return {}


def calculate_blur_score(image_path: str):
    image = cv2.imread(image_path)
    if image is None:
        return 0.0
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def calculate_smoothness_score(image_path: str):
    image = cv2.imread(image_path)
    if image is None:
        return 0.0

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 100, 200)
    edge_density = float(np.count_nonzero(edges)) / float(edges.size)
    smoothness = max(0.0, 100.0 - edge_density * 1000.0)
    return round(min(smoothness, 100.0), 2)


def analyze_image(image_path: str):
    image = cv2.imread(image_path)
    if image is None:
        return {
            "success": False,
            "message": "无法读取图片文件"
        }

    height, width = image.shape[:2]
    exif_data = get_exif_data(image_path)
    has_exif = len(exif_data) > 0
    blur_score = calculate_blur_score(image_path)
    smoothness_score = calculate_smoothness_score(image_path)

    points = []
    risk_score = 0

    if not has_exif:
        points.append("图像元数据缺失")
        risk_score += 20

    if blur_score < 80:
        points.append("图像清晰度偏低，存在模糊痕迹")
        risk_score += 20

    if smoothness_score > 70:
        points.append("局部区域可能存在过度平滑现象")
        risk_score += 20

    if width == height and width >= 1024:
        points.append("图片尺寸较规则，需结合生成来源进一步判断")
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
        "type": "image",
        "risk_level": risk_level,
        "score": risk_score,
        "points": points,
        "details": {
            "width": width,
            "height": height,
            "has_exif": has_exif,
            "blur_score": round(blur_score, 2),
            "smoothness_score": smoothness_score,
            "exif_fields": list(exif_data.keys())[:10]
        },
        "message": "图片分析完成"
    }
