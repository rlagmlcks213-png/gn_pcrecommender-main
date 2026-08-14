# -*- coding: utf-8 -*-

# danawa_cralwer.py
# sammy310


from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

from datetime import datetime
from datetime import timedelta
from pytz import timezone
import csv
import os
import os.path
import shutil
import traceback
import time

from multiprocessing import Pool

from github import Github

IS_TEST = False
#IS_TEST = True

PROCESS_COUNT = 2

GITHUB_TOKEN_KEY = 'MY_GITHUB_TOKEN'
# [수정] 실제로 워크플로우가 도는 저장소로 변경 (기존 'sammy310/Danawa-Crawler'는 원본/포크 이전 저장소라
#        여기서는 권한이 없거나 엉뚱한 곳에 이슈가 생길 수 있었음)
GITHUB_REPOSITORY_NAME = 'neungjichai/Danawa-crawler-fix'

CRAWLING_DATA_CSV_FILE = 'CrawlingCategory.csv'
if IS_TEST:
    CRAWLING_DATA_CSV_FILE = 'CrawlingCategory_test.csv'

DATA_PATH = 'crawl_data'
DATA_REFRESH_PATH = f'{DATA_PATH}/Last_Data'

TIMEZONE = 'Asia/Seoul'

CHROMEDRIVER_PATH = 'chromedriver'
if IS_TEST:
    CHROMEDRIVER_PATH = 'chromedriver_112.exe'

DATA_DIVIDER = '---'
DATA_REMARK = '//'
DATA_ROW_DIVIDER = '_'
DATA_PRODUCT_DIVIDER = '|'

STR_NAME = 'name'
STR_URL = 'url'
STR_CRAWLING_PAGE_SIZE = 'crawlingPageSize'

# ============================================================
# 취급 회사(브랜드) 제한 - CrawlingCategory.csv의 카테고리명(STR_NAME) 기준
# 여기서 걸러진 상품은 아예 CSV에 기록하지 않음 (크롤링 단계 필터링).
# generate_sql.py의 BRAND_INCLUDE_KEYWORDS / CHIP_EXCLUDE_KEYWORDS 와 반드시 동일하게 유지할 것.
# ============================================================
BRAND_INCLUDE_KEYWORDS = {
    'MBoard': ['MSI', 'ASUS', '에이수스'],
    'Cooler': ['DEEPCOOL', '딥쿨'],
    'RAM':    ['삼성전자', 'TeamGroup', '팀그룹'],
    'SSD':    ['삼성전자'],
    'HDD':    ['Western Digital', 'WD ', '웬디'],
    'Power':  ['마이크로닉스'],
    'Case':   ['darkFlash', '다크플래시', '앱코', 'ABKO'],
}

CHIP_EXCLUDE_KEYWORDS = {
    'CPU': ['AMD', '라이젠', 'Ryzen', '스레드리퍼', 'Threadripper', 'EPYC', '라파엘', '그라도'],
    'VGA': ['라데온', 'Radeon', 'RADEON', '인텔 아크', 'Intel Arc', ' Arc '],
}


def IsBrandAllowed(crawlingName, productName):
    """이 카테고리에 브랜드/칩 제한이 걸려있다면 productName이 조건을 만족하는지 확인.
    제한이 없는 카테고리(Monitor, Keyboard 등)는 항상 True."""
    if crawlingName in BRAND_INCLUDE_KEYWORDS:
        return any(kw in productName for kw in BRAND_INCLUDE_KEYWORDS[crawlingName])
    if crawlingName in CHIP_EXCLUDE_KEYWORDS:
        return not any(kw in productName for kw in CHIP_EXCLUDE_KEYWORDS[crawlingName])
    return True


class DanawaCrawler:
    def __init__(self):
        self.errorList = list()
        self.crawlingCategory = list()
        with open(CRAWLING_DATA_CSV_FILE, 'r', newline='') as file:
            for crawlingValues in csv.reader(file, skipinitialspace=True):
                if not crawlingValues[0].startswith(DATA_REMARK):
                    self.crawlingCategory.append({STR_NAME: crawlingValues[0], STR_URL: crawlingValues[1], STR_CRAWLING_PAGE_SIZE: int(crawlingValues[2])})

    def StartCrawling(self):
        self.chrome_option = Options()
        self.chrome_option.add_argument('--headless=new')
        self.chrome_option.add_argument('--window-size=1920x1080')
        self.chrome_option.add_argument('--start-maximized')
        self.chrome_option.add_argument('--disable-gpu')
        self.chrome_option.add_argument('lang=ko=KR')
        # [수정] 실제 설치된 Chrome(151.x)과 UA 버전을 맞춤.
        #        UA와 실제 브라우저 버전이 크게 다르면 일부 사이트가 봇으로 의심해
        #        비정상 페이지(캡차/인터스티셜 등)를 내려줘서 로딩이 끝나지 않을 수 있음.
        custom_user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36'
        self.chrome_option.add_argument(f'user-agent={custom_user_agent}')
        self.chrome_option.add_argument('--no-sandbox')
        self.chrome_option.add_argument('--disable-dev-shm-usage')


        if __name__ == '__main__':
            pool = Pool(processes=PROCESS_COUNT)
            # [수정] multiprocessing.Pool은 각 워커가 별도 프로세스이므로,
            #        자식 프로세스 안에서 self.errorList.append(...)를 해도
            #        부모(메인) 프로세스의 self.errorList에는 절대 반영되지 않음.
            #        (self 객체 자체가 pickle되어 각 프로세스로 "복사"되기 때문)
            #        그래서 CrawlingCategory가 실패한 카테고리명을 "리턴값"으로 넘기게 하고,
            #        pool.map의 결과(results)를 부모 프로세스에서 모아서 errorList를 채운다.
            results = pool.map(self.CrawlingCategory, self.crawlingCategory)
            pool.close()
            pool.join()

            self.errorList = [name for name in results if name is not None]

    def CrawlingCategory(self, categoryValue):
        crawlingName = categoryValue[STR_NAME]
        crawlingURL = categoryValue[STR_URL]
        crawlingSize = categoryValue[STR_CRAWLING_PAGE_SIZE]
 
        print('Crawling Start : ' + crawlingName)
 
        # data
        crawlingFile = open(f'{crawlingName}.csv', 'w', newline='', encoding='utf8')
        crawlingData_csvWriter = csv.writer(crawlingFile)
        crawlingData_csvWriter.writerow([self.GetCurrentDate().strftime('%Y-%m-%d %H:%M:%S')])
 
        # [수정] finally에서 browser.quit()을 반드시 호출하기 위해 try 밖에서 선언
        browser = None
        try:
            browser = webdriver.Chrome(options=self.chrome_option)
            browser.implicitly_wait(5)
            # [수정] browser.get()은 기본적으로 페이지의 모든 리소스가 로드될 때까지
            #        "무한정" 대기할 수 있음. 봇 감지/네트워크 문제 등으로 특정 리소스가
            #        응답을 안 주면 워크플로우 전체가 수십 분씩 멈추는 원인이 됨.
            #        30초 안에 로딩이 끝나지 않으면 TimeoutException을 발생시켜
            #        except 블록에서 정상적으로 다음 카테고리로 넘어가게 함.
            browser.set_page_load_timeout(30)
            browser.get(crawlingURL)

            # [수정] 페이지 진입 직후 뜨는 모달/팝업(공지, 쿠키 동의 등)이
            #        정렬 버튼 클릭을 가로채는 문제(ElementClickInterceptedException) 방지.
            #        모달이 있으면 DOM에서 강제로 제거하고, 없으면 그냥 넘어감.
            self.CloseModalIfExists(browser)

            browser.find_element(By.XPATH, '//option[@value="90"]').click()
 
            wait = WebDriverWait(browser, 10)
            wait.until(EC.invisibility_of_element((By.CLASS_NAME, 'product_list_cover')))
 
            for i in range(-1, crawlingSize):
                # [수정] 혹시 페이지 이동/갱신 중 다시 모달이 뜰 수 있으므로 매 루프마다 한 번 더 체크
                self.CloseModalIfExists(browser)

                if i == -1:
                    self.SafeClick(browser, browser.find_element(By.XPATH, '//li[@data-sort-method="NEW"]'))
                elif i == 0:
                    self.SafeClick(browser, browser.find_element(By.XPATH, '//li[@data-sort-method="BEST"]'))
                elif i > 0:
                    if i % 10 == 0:
                        self.SafeClick(browser, browser.find_element(By.XPATH, '//a[@class="edge_nav nav_next"]'))
                    else:
                        self.SafeClick(browser, browser.find_element(By.XPATH, '//a[@class="num "][%d]' % (i % 10)))
 
                wait.until(EC.invisibility_of_element((By.CLASS_NAME, 'product_list_cover')))
 
                # Get Product List
                productListDiv = browser.find_element(By.XPATH, '//div[@class="main_prodlist main_prodlist_list"]')
 
                # [수정 1] '//' -> './/' 로 바꿔서 productListDiv 내부에서만 검색하도록 함
                #          (기존 '//'는 문서 전체를 검색해서 광고 영역 ul까지 섞여 들어옴)
                #
                # [수정 2] 로딩 스피너(product_list_cover) 대기가 더 이상 안 먹힐 수 있어서,
                #          실제로 상품 <li>가 하나 이상 나타날 때까지 최대 10초 재시도.
                #          다나와가 로딩 스피너 클래스명을 바꿔서 예전 wait가 사실상
                #          0초로 통과되는 경우를 대비한 이중 안전장치.
                products = []
                for attempt in range(10):
                    products = productListDiv.find_elements(By.XPATH, './/ul[@class="product_list"]/li')
                    if len(products) > 0:
                        break
                    time.sleep(2)
 
                if len(products) == 0:
                    # 재시도까지 다 실패하면, 이 페이지는 건너뛰지 말고 명확히 에러로 기록
                    raise Exception(f'{crawlingName} page {i}: 상품 목록을 찾지 못함 (products=0)')
 
                for product in products:
                    if not product.get_attribute('id'):
                        continue
 
                    # ad
                    if 'prod_ad_item' in product.get_attribute('class').split(' '):
                        continue
                    if product.get_attribute('id').strip().startswith('ad'):
                        continue
 
                    productId = product.get_attribute('id')[11:]
                    productName = product.find_element(By.XPATH, './div/div[2]/p/a').text.strip()
                    productPrices = product.find_elements(By.XPATH, './div/div[3]/ul/li')
                    productPriceStr = ''
 
                    # Check Mall
                    isMall = False
                    if 'prod_top5' in product.find_element(By.XPATH, './div/div[3]').get_attribute('class').split(' '):
                        isMall = True
 
                    if isMall:
                        for productPrice in productPrices:
                            if 'top5_button' in productPrice.get_attribute('class').split(' '):
                                continue
 
                            if productPriceStr:
                                productPriceStr += DATA_PRODUCT_DIVIDER
 
                            mallName = productPrice.find_element(By.XPATH, './a/div[1]').text.strip()
                            if not mallName:
                                mallName = productPrice.find_element(By.XPATH, './a/div[1]/span[1]').text.strip()
 
                            price = productPrice.find_element(By.XPATH, './a/div[2]/em').text.strip()
 
                            productPriceStr += f'{mallName}{DATA_ROW_DIVIDER}{price}'
                    else:
                        for productPrice in productPrices:
                            if productPriceStr:
                                productPriceStr += DATA_PRODUCT_DIVIDER
 
                            productType = productPrice.find_element(By.XPATH, './div/p').text.strip()
                            productType = productType.replace('\n', DATA_ROW_DIVIDER)
                            productType = self.RemoveRankText(productType)
 
                            price = productPrice.find_element(By.XPATH, './p[2]/a/strong').text.strip()
 
                            if productType:
                                productPriceStr += f'{productType}{DATA_ROW_DIVIDER}{price}'
                            else:
                                productPriceStr += f'{price}'
 
                    # 취급 회사(브랜드)/칩 제조사 제한에 안 맞으면 아예 기록하지 않음
                    if not IsBrandAllowed(crawlingName, productName):
                        continue

                    crawlingData_csvWriter.writerow([productId, productName, productPriceStr])

        except Exception as e:
            print('Error - ' + crawlingName + ' ->')
            print(traceback.format_exc())
            # [수정] 여기서 self.errorList.append(...)를 해도 부모 프로세스에는 반영되지 않으므로
            #        (multiprocessing.Pool의 각 워커는 별도 프로세스) 대신 실패를 리턴값으로 알린다.
            crawlingFile.close()
            print('Crawling Finish : ' + crawlingName)
            return crawlingName

        finally:
            # [수정] 예외가 나든 안 나든 브라우저는 반드시 종료.
            #        종료를 안 하면 좀비 chrome/chromedriver 프로세스가 쌓여
            #        이후 카테고리 크롤링에도 영향(리소스 부족, 실행 지연 등)을 줄 수 있음.
            if browser is not None:
                try:
                    browser.quit()
                except Exception:
                    pass

        crawlingFile.close()
 
        print('Crawling Finish : ' + crawlingName)
        return None

    def CloseModalIfExists(self, browser, timeout=3):
        """페이지에 뜨는 모달(<modal-widget> 등)이 있으면 DOM에서 강제로 제거한다.
        모달이 클릭을 가로채서 ElementClickInterceptedException이 나는 문제를 방지."""
        try:
            WebDriverWait(browser, timeout).until(
                EC.presence_of_element_located((By.CSS_SELECTOR, 'modal-widget'))
            )
            browser.execute_script(
                "document.querySelectorAll('modal-widget').forEach(function(e){ e.remove(); });"
            )
        except Exception:
            # 모달이 없거나 timeout이면 그냥 넘어감
            pass

    def SafeClick(self, browser, element):
        """일반 click()이 다른 요소(모달 등)에 가로채질 경우를 대비해
        JS 강제 클릭으로 한 번 더 시도한다."""
        try:
            element.click()
        except Exception:
            browser.execute_script("arguments[0].click();", element)

    def RemoveRankText(self, productText):
        if len(productText) < 2:
            return productText
        
        char1 = productText[0]
        char2 = productText[1]

        if char1.isdigit() and (1 <= int(char1) and int(char1) <= 9):
            if char2 == '위':
                return productText[2:].strip()
        
        return productText

    def DataSort(self):
        print('Data Sort\n')

        for crawlingValue in self.crawlingCategory:
            dataName = crawlingValue[STR_NAME]
            crawlingDataPath = f'{dataName}.csv'

            if not os.path.exists(crawlingDataPath):
                continue

            crawl_dataList = list()
            dataList = list()
            
            with open(crawlingDataPath, 'r', newline='', encoding='utf8') as file:
                csvReader = csv.reader(file)
                for row in csvReader:
                    crawl_dataList.append(row)
            
            if len(crawl_dataList) == 0:
                continue
            
            dataPath = f'{DATA_PATH}/{dataName}.csv'
            if not os.path.exists(dataPath):
                file = open(dataPath, 'w', encoding='utf8')
                file.close()
            with open(dataPath, 'r', newline='', encoding='utf8') as file:
                csvReader = csv.reader(file)
                for row in csvReader:
                    dataList.append(row)
            
            
            if len(dataList) == 0:
                dataList.append(['Id', 'Name'])
                
            dataList[0].append(crawl_dataList[0][0])
            dataSize = len(dataList[0])
            
            for product in crawl_dataList:
                if not str(product[0]).isdigit():
                    continue
                
                isDataExist = False
                for data in dataList:
                    if data[0] == product[0]:
                        if len(data) < dataSize:
                            data.append(product[2])
                        isDataExist = True
                        break
                
                if not isDataExist:
                    newDataList = ([product[0], product[1]])
                    for i in range(2,len(dataList[0])-1):
                        newDataList.append(0)
                    newDataList.append(product[2])
                
                    dataList.append(newDataList)
                
            for data in dataList:
                if len(data) < dataSize:
                    for i in range(len(data),dataSize):
                        data.append(0)
                
            
            productData = dataList.pop(0)
            dataList.sort(key= lambda x: x[1])
            dataList.insert(0, productData)
                
            with open(dataPath, 'w', newline='', encoding='utf8') as file:
                csvWriter = csv.writer(file)
                for data in dataList:
                    csvWriter.writerow(data)
                file.close()
                
            if os.path.isfile(crawlingDataPath):
                os.remove(crawlingDataPath)

    def DataRefresh(self):
        dTime = self.GetCurrentDate()
        if dTime.day == 1:
            print('Data Refresh\n')

            if not os.path.exists(DATA_PATH):
                os.mkdir(DATA_PATH)
            
            dTime -= timedelta(days=1)
            dateStr = dTime.strftime('%Y-%m')

            dataSavePath = f'{DATA_REFRESH_PATH}/{dateStr}'
            if not os.path.exists(dataSavePath):
                os.mkdir(dataSavePath)
            
            for file in os.listdir(DATA_PATH):
                fileName, fileExt = os.path.splitext(file)
                if fileExt == '.csv':
                    filePath = f'{DATA_PATH}/{file}'
                    refreshFilePath = f'{dataSavePath}/{file}'
                    shutil.move(filePath, refreshFilePath)
    
    def GetCurrentDate(self):
        tz = timezone(TIMEZONE)
        return (datetime.now(tz))

    def CreateIssue(self):
        if len(self.errorList) > 0:
            g = Github(os.environ[GITHUB_TOKEN_KEY])
            repo = g.get_repo(GITHUB_REPOSITORY_NAME)
            
            title = f'Crawling Error - ' + self.GetCurrentDate().strftime('%Y-%m-%d')
            body = ''
            for err in self.errorList:
                body += f'- {err}\n'

            # [수정] 라벨 조회/부여 권한이 없거나(403) 라벨이 존재하지 않는 경우(404)에도
            #        이슈 생성 자체는 실패하지 않도록 분리. 실패 시 라벨 없이 이슈 생성.
            labels = []
            try:
                labels = [repo.get_label('bug')]
            except Exception as e:
                print(f'Warning: failed to get label "bug" ({e}), creating issue without label.')

            repo.create_issue(title=title, body=body, labels=labels)
        


if __name__ == '__main__':
    crawler = DanawaCrawler()
    crawler.DataRefresh()
    crawler.StartCrawling()
    crawler.DataSort()
    crawler.CreateIssue()
