r"""
danawa_only_load.sql 안에 박혀있는 LOAD DATA LOCAL INFILE 경로를
실제 이 컴퓨터의 crawl_data 폴더 경로로 바꿔주는 스크립트.

사용법:
    python fix_csv_path.py <원본_sql_경로> <실제_crawl_data_폴더_경로>

예:
    python fix_csv_path.py New_crawler\danawa_only_load.sql New_crawler\crawl_data
"""
import re
import sys


def read_any_encoding(path: str) -> str:
    for enc in ["utf-8", "utf-8-sig", "utf-16", "utf-16-le", "cp949"]:
        try:
            with open(path, encoding=enc) as f:
                return f.read()
        except (UnicodeDecodeError, UnicodeError):
            continue
    raise ValueError(f"인코딩을 인식하지 못했습니다: {path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("사용법: python fix_csv_path.py <sql파일경로> <crawl_data폴더경로>")
        sys.exit(1)

    sql_path = sys.argv[1]
    new_dir = sys.argv[2].replace("\\", "/").rstrip("/")

    content = read_any_encoding(sql_path)

    # 'LOAD DATA LOCAL INFILE '아무경로/파일명.csv'' 형태를 찾아서
    # 폴더 부분만 new_dir로 교체(파일명은 그대로 유지)
    def replace_path(match):
        filename = match.group(1)
        return f"LOAD DATA LOCAL INFILE '{new_dir}/{filename}'"

    new_content = re.sub(
        r"LOAD DATA LOCAL INFILE '[^']*?/([^/']+\.csv)'",
        replace_path,
        content,
    )

    count = len(re.findall(r"LOAD DATA LOCAL INFILE", content))
    out_path = sql_path.rsplit(".", 1)[0] + "_fixed.sql"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(new_content)

    print(f"경로 {count}개 교체 완료 -> {out_path}")
    print(f"이제 이걸 실행하세요: python db\\load_real_data.py {out_path}")
