import telebot, os, time
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.chrome.options import Options

bot = telebot.TeleBot('8272419168:AAE7PA_EkqnDr30J71fhz4jMPhpcjD1NtC0')

@bot.message_handler(commands=['run'])
def start(message):
    bot.send_message(message.chat.id, "🚀 جاري تشغيل Titan على سيرفر Koyeb المستقر...")
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    # مسار الكروم التلقائي في Koyeb
    try:
        driver = webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=options)
        driver.get("https://1xlite-864094.top/")
        time.sleep(10)
        driver.save_screenshot("view.png")
        with open("view.png", "rb") as f:
            bot.send_photo(message.chat.id, f, caption="🔓 الاختراق السحابي نجح! السيرفر يعمل 100%.")
        driver.quit()
    except Exception as e:
        bot.send_message(message.chat.id, f"⚠️ خطأ: {str(e)}")

bot.polling()
