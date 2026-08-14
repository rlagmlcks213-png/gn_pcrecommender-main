# -*- coding: utf-8 -*-
"""
다나와 상품 상세페이지 상단의 "핵심 스펙 요약 한 줄"을 긁어와서
MySQL에 저장하는 스크래퍼.

예: "RTX 5060 Ti / PCIe5.0×16(at x8) / 600W 이상 / 전원 포트 : 8핀 x1 / ..."
이 한 줄을 항목별로 쪼개서 저장합니다.

주의:
- 이 스크립트는 danawa.com에 실제로 접속해야 하므로, 반드시 본인 PC(네트워크
  제한이 없는 환경)에서 실행해야 합니다.
- 다나와 페이지 구조는 카테고리마다, 또 시점에 따라 달라질 수 있어서
  아래 SPEC_SELECTORS 후보들을 순서대로 시도합니다. 만약 전부 실패하면
  DEBUG_HTML_DUMP=True 로 켜서 실제 저장된 HTML을 보고 셀렉터를 조정하세요.
- 다나와 서버에 부담을 주지 않도록 요청 사이 REQUEST_DELAY 초만큼 쉽니다.
  너무 짧게 잡으면 IP 차단될 수 있으니 1~2초 이상 권장합니다.

사용법:
    pip install requests beautifulsoup4 mysql-connector-python
    python danawa_spec_scraper.py --category cpu --limit 5      # 테스트
    python danawa_spec_scraper.py --category cpu                # 전체
"""

import argparse
import re
import time
import sys
import os

import requests
from bs4 import BeautifulSoup
import mysql.connector

REQUEST_DELAY = 2.0  # 요청 간 대기 시간(초). 다나와 서버 부담을 줄이기 위함
DEBUG_HTML_DUMP = False  # True로 하면 첫 실패 시 HTML을 debug_dump.html로 저장

DB_CONFIG = {
    "host": os.environ.get("DANAWA_DB_HOST", "localhost"),
    "port": int(os.environ.get("DANAWA_DB_PORT", "3306")),
    "user": os.environ.get("DANAWA_DB_USER", "root"),
    "password": os.environ.get("DANAWA_DB_PASSWORD", "JH84952"),
    "database": os.environ.get("DANAWA_DB_NAME", "DW_db"),
    "charset": "utf8mb4",
}

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "ko-KR,ko;q=0.9",
}

DETAIL_URL = "https://prod.danawa.com/info/?pcode={pcode}"

# 페이지 구조가 바뀌었을 때를 대비해 여러 후보 셀렉터를 순서대로 시도
SPEC_SELECTORS = [
    ("div", {"class": "spec_list"}),
    ("div", {"class": "top_summary"}),
    ("div", {"class": "prod_spec_summary"}),
    ("dl", {"class": "spec_list"}),
]


def fetch_spec_summary(pcode: str):
    """상품 상세페이지의 <meta name="Description"> 태그에서
    "요약정보 : ..." 뒤에 오는 핵심 스펙 한 줄을 가져와서
    [(spec_key_or_None, spec_value), ...] 리스트로 반환.

    예) meta Description 내용:
    "컴퓨터/노트북/조립PC,주요부품,그래픽카드(VGA), ZOTAC ... ,
     요약정보 : RTX 5060 Ti / PCIe5.0x16(at x8) / 600W 이상 / ..."
    """
    url = DETAIL_URL.format(pcode=pcode)
    resp = requests.get(url, headers=HEADERS, timeout=10)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    # ---- 이미지 URL (og:image 메타태그 - 페이지 디자인 변경에 영향 안 받음) ----
    image_url = None
    og_image = soup.find("meta", attrs={"property": "og:image"})
    if og_image and og_image.get("content"):
        image_url = og_image["content"].strip()

    raw_text = None

    # 1순위: meta Description 태그 (가장 안정적 - 페이지 디자인 변경에 영향 안 받음)
    meta = soup.find("meta", attrs={"name": re.compile(r"^description$", re.I)})
    if meta and meta.get("content"):
        content = meta["content"]
        if "요약정보" in content:
            raw_text = content.split("요약정보", 1)[1].lstrip(" :")

    # 2순위 (fallback): 본문에서 "상세 스펙" 라벨 뒤 텍스트 블록 찾기
    if raw_text is None:
        label = soup.find(string=re.compile(r"^\s*상세\s*스펙\s*$"))
        if label:
            # 라벨 바로 다음 형제/부모의 텍스트를 스펙 줄로 사용
            parent = label.find_parent()
            nxt = parent.find_next_sibling() if parent else None
            if nxt:
                raw_text = nxt.get_text(separator="/", strip=True)

    if raw_text is None:
        if DEBUG_HTML_DUMP:
            with open("debug_dump.html", "w", encoding="utf8") as f:
                f.write(resp.text)
            print(f"  [경고] {pcode}: 스펙 요약을 못 찾음. debug_dump.html 저장함")
        return [], image_url

    # "RTX 5060 Ti / PCIe5.0x16(at x8) / 600W 이상 / 전원 포트: 8핀 x1 / ..."
    parts = [p.strip() for p in raw_text.split("/") if p.strip()]

    results = []
    for part in parts:
        if ":" in part:
            k, v = part.split(":", 1)
            results.append((k.strip(), v.strip()))
        else:
            results.append((None, part))  # 키 없이 값만 있는 항목 (칩셋명 등)
    return results, image_url


def ensure_table(cursor):
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS danawa_spec_summary (
            id          BIGINT AUTO_INCREMENT PRIMARY KEY,
            category    VARCHAR(20) NOT NULL,
            product_id  BIGINT UNSIGNED NOT NULL,
            spec_key    VARCHAR(150),
            spec_value  VARCHAR(300) NOT NULL,
            spec_order  INT NOT NULL,
            scraped_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            KEY idx_lookup (category, product_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS product_media (
            category    VARCHAR(20) NOT NULL,
            product_id  BIGINT UNSIGNED NOT NULL,
            image_url   VARCHAR(500),
            product_url VARCHAR(300),
            scraped_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (category, product_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--category", help="예: cpu, ram, mboard 등 (--all과 함께 쓸 수 없음)")
    parser.add_argument("--all", action="store_true", help="10개 카테고리 전부 순서대로 실행")
    parser.add_argument("--limit", type=int, default=None, help="테스트용 개수 제한")
    parser.add_argument("--force", action="store_true", help="이미 스크랩된 상품도 다시 긁기 (기본은 건너뜀)")
    args = parser.parse_args()

    ALL_CATEGORIES = ["cpu", "ram", "mboard", "ssd", "hdd", "power", "cooler", "case", "monitor", "vga"]

    if args.all:
        categories = ALL_CATEGORIES
    elif args.category:
        categories = [args.category]
    else:
        print("--category 또는 --all 중 하나는 지정해야 합니다.")
        sys.exit(1)

    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()
    ensure_table(cursor)
    conn.commit()

    log_path = "scrape_progress.log"

    for category in categories:
        table = f"{category}_products"
        cursor.execute(f"SELECT product_id, name FROM `{table}`")
        rows = cursor.fetchall()

        if not args.force:
            cursor.execute(
                "SELECT DISTINCT product_id FROM danawa_spec_summary WHERE category=%s",
                (category,),
            )
            spec_done = {r[0] for r in cursor.fetchall()}
            cursor.execute(
                "SELECT DISTINCT product_id FROM product_media WHERE category=%s",
                (category,),
            )
            media_done = {r[0] for r in cursor.fetchall()}
            # 스펙 + 이미지 둘 다 이미 있는 상품만 건너뜀
            # (예전에 스펙만 긁고 이미지는 없던 상품은 이번에 이미지만 채워짐)
            already_done = spec_done & media_done
            rows = [r for r in rows if r[0] not in already_done]

        if args.limit:
            rows = rows[: args.limit]

        print(f"\n===== [{category}] 대상 {len(rows)}개 (이미 완료된 건 자동 제외) =====")
        success, fail = 0, 0

        for i, (pid, name) in enumerate(rows, 1):
            specs, image_url, err = None, None, None
            for attempt in range(3):  # 최대 3회 재시도
                try:
                    specs, image_url = fetch_spec_summary(str(pid))
                    err = None
                    break
                except Exception as e:
                    err = e
                    time.sleep(3)  # 재시도 전 조금 더 대기

            log_line = f"[{category}] [{i}/{len(rows)}] pid={pid} name={name}"

            if err is not None:
                fail += 1
                log_line += f" -> 실패(에러): {err}"
            elif not specs:
                fail += 1
                log_line += " -> 실패(스펙 없음)"
            else:
                cursor.execute(
                    "DELETE FROM danawa_spec_summary WHERE category=%s AND product_id=%s",
                    (category, pid),
                )
                insert_vals = [
                    (category, pid, k, v, idx) for idx, (k, v) in enumerate(specs)
                ]
                cursor.executemany(
                    """INSERT INTO danawa_spec_summary
                       (category, product_id, spec_key, spec_value, spec_order)
                       VALUES (%s,%s,%s,%s,%s)""",
                    insert_vals,
                )
                success += 1
                log_line += f" -> 성공({len(specs)}개 항목)"

            # 스펙 파싱 성공/실패와 별개로, 페이지 접속 자체가 됐으면
            # 이미지/상품페이지 URL은 저장 (image_url이 없으면 NULL로 저장됨)
            if err is None:
                product_url = DETAIL_URL.format(pcode=pid)
                cursor.execute(
                    """INSERT INTO product_media (category, product_id, image_url, product_url)
                       VALUES (%s,%s,%s,%s)
                       ON DUPLICATE KEY UPDATE image_url=VALUES(image_url), product_url=VALUES(product_url)""",
                    (category, pid, image_url, product_url),
                )

            conn.commit()

            print(log_line)
            with open(log_path, "a", encoding="utf8") as lf:
                lf.write(log_line + "\n")

            time.sleep(REQUEST_DELAY)

        print(f"[{category}] 완료: 성공 {success} / 실패 {fail}")

    cursor.close()
    conn.close()
    print("\n전체 작업 완료.")


if __name__ == "__main__":
    main()