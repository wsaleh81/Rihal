import Foundation

/// Arabic interface strings. When the app language is Arabic every label goes through `L`.
enum Loc {
    static var ar: Bool { (UserDefaults.standard.string(forKey: "langID") ?? "ar") == "ar" }
    static var langID: String { UserDefaults.standard.string(forKey: "langID") ?? "ar" }
    static var isX: Bool { LocX.ids.contains(langID) }
    static var hasUI: Bool { LocX.ui[langID] != nil }
    static var dateLocale: Locale { Locale(identifier: ar ? "ar-u-nu-latn" : (hasUI ? "\(langID)-u-nu-latn" : "en_GB")) }
    /// Translated message template ({0}, {1} are replaced). Falls back to the English template.
    static func f(_ t: String, _ a: String...) -> String {
        var x = LocX.tpl[langID]?[t] ?? LocNew.ui[langID]?[t] ?? t
        for (i, v) in a.enumerated() { x = x.replacingOccurrences(of: "{\(i)}", with: v) }
        return x
    }
    static let map: [String: String] = [
        "accessibility": "إمكانية الوصول", "Text size": "حجم الخط", "Auto (iPhone setting)": "تلقائي (إعداد الآيفون)",
        "Standard": "عادي", "Large": "كبير", "Larger": "أكبر", "Largest": "الأكبر", "Azkhar text size": "حجم خط الأذكار", "Bold text": "خط عريض", "font": "الخط", "Compass style": "شكل البوصلة", "Classic": "كلاسيكي", "Rings": "دوائر", "App font": "خط التطبيق", "System default": "خط النظام (الافتراضي)",
        // tabs & titles
        "Qibla": "القبلة", "Prayer Times": "مواقيت الصلاة", "Mosques": "المساجد", "Azkhar": "الأذكار", "Mushaf": "المصحف", "Settings": "الإعدادات",
        // settings headers
        "theme": "المظهر", "language": "اللغة", "prayers": "الصلاة", "notifications": "التنبيهات", "compass": "البوصلة",
        "Theme": "المظهر", "Appearance": "الوضع", "Auto": "تلقائي", "Light": "فاتح", "Dark": "داكن",
        "Ocean": "المحيط", "Emerald": "الزمرد", "Royal": "الملكي", "Sunset": "الغروب", "Rose": "الوردي", "Graphite": "الجرافيت",
        "Prayer names": "أسماء الصلوات", "Application language": "لغة التطبيق", "units": "الوحدات", "Celsius (°C)": "سيلسيوس (°م)", "Fahrenheit (°F)": "فهرنهايت (°ف)", "Language": "اللغة", "Temperature": "درجة الحرارة", "Temperature unit": "وحدة الحرارة",
        "City": "المدينة", "Current location": "الموقع الحالي", "Choose a city": "اختر مدينة", "Local time": "الوقت المحلي", "Use my location": "استخدم موقعي", "Detect location automatically": "تحديد الموقع تلقائيًا",
        "Location is off for this app. Turn it on in iPhone Settings, or choose a city.": "الموقع مغلق لهذا التطبيق. فعّله من إعدادات الآيفون أو اختر مدينة.",
        "Method": "طريقة الحساب", "Adjust times": "تعديل الأوقات", "minutes": "دقائق", "Hanafi Asr": "العصر على المذهب الحنفي", "Show current prayer (Now)": "إظهار الصلاة الحالية (الآن)",
        "Adhan alerts": "تنبيهات الأذان", "Notifications are off for this app in iPhone Settings.": "التنبيهات مغلقة لهذا التطبيق في إعدادات الآيفون.",
        "Remind": "التذكير قبل", "Off": "إيقاف", "min": "د", "Sunrise alert": "تنبيه الشروق",
        "Tap the bell next to a prayer to mute just that prayer.": "اضغط على الجرس بجانب الصلاة لكتم تنبيهها فقط.",
        "Preview mode (turn dial by hand)": "وضع المعاينة (تدوير البوصلة باليد)", "About": "حول التطبيق",
        "Qibla and prayer times are calculated on this device. Your approximate location is sent only when you look up mosques, weather or cities.": "القبلة ومواقيت الصلاة تُحسب على هذا الجهاز. يُرسل موقعك التقريبي فقط عند البحث عن المساجد أو الطقس أو المدن.",
        "Add or subtract minutes to match your local mosque or official timetable.": "أضف دقائق أو اطرحها لتطابق مسجدك المحلي أو الجدول الرسمي.",
        "Fajr": "الفجر", "Sunrise": "الشروق", "Dhuhr": "الظهر", "Asr": "العصر", "Maghrib": "المغرب", "Isha": "العشاء",
        "Done": "تم", "Cancel": "إلغاء",
        // methods
        "Kuwait": "الكويت", "Muslim World League": "رابطة العالم الإسلامي", "Egyptian General Authority": "الهيئة المصرية العامة للمساحة",
        "Karachi (UIS)": "كراتشي", "ISNA (North America)": "أمريكا الشمالية (ISNA)", "Umm al-Qura (Makkah)": "أم القرى (مكة المكرمة)",
        "MWL": "رابطة العالم", "Egypt": "مصر", "Karachi": "كراتشي", "ISNA": "أمريكا الشمالية", "Umm al-Qura": "أم القرى",
        // city picker
        "Search city, country or code": "ابحث عن مدينة أو دولة أو رمز", "No city found. Try another spelling.": "لم يتم العثور على مدينة. جرّب كتابة أخرى.",
        "No match offline. Connect to the internet to search more cities.": "لا توجد نتيجة دون اتصال. اتصل بالإنترنت للبحث عن مدن أكثر.",
        "More results": "المزيد من النتائج", "Near me": "بالقرب مني",
        // prayer view
        "NOW": "الآن", "NEXT": "التالية", "Refresh": "تحديث", "Use GPS": "استخدم GPS", "Choose city": "اختر مدينة",
        "Finding your location…": "جارٍ تحديد موقعك…", "Manual city": "مدينة يدوية", "Location not found": "لم يتم العثور على الموقع",
        "Not available here": "غير متاح هنا", "just now": "الآن",
        // mosques
        "You are offline": "أنت غير متصل", "Finding mosques needs internet. Prayer times and Qibla keep working without it.": "البحث عن المساجد يحتاج إلى الإنترنت. مواقيت الصلاة والقبلة تعملان دونه.",
        "Looking for mosques…": "جارٍ البحث عن المساجد…", "Couldn’t search": "تعذّر البحث", "Check your connection and tap refresh.": "تحقق من الاتصال ثم اضغط تحديث.",
        "No mosques found nearby": "لا توجد مساجد قريبة", "Try another city from the menu above.": "جرّب مدينة أخرى من القائمة أعلاه.",
        "Sources: Apple Maps and © OpenStreetMap contributors. A seal means both list the mosque. Distances are straight-line from your position.": "المصادر: خرائط آبل و © مساهمو OpenStreetMap. الختم يعني أن المصدرين يذكران المسجد. المسافات بخط مستقيم من موقعك.",
        "Open in Apple Maps": "فتح في خرائط آبل", "Open in Google Maps": "فتح في خرائط جوجل", "Open in Waze": "فتح في Waze",
        "Confirmed": "مؤكد", "Mosque": "مسجد", "Find mosques in": "ابحث عن مساجد في", "walk": "سيرًا", "m": "م", "km": "كم",
        // qibla
        "Sunrise ": "الشروق", "Distance": "المسافة", "km to Makkah": "كم إلى مكة", "Finding the compass": "جارٍ تشغيل البوصلة",
        "You're facing the Qibla": "أنت تواجه القبلة", "Hold steady, then begin your prayer": "اثبت ثم ابدأ صلاتك",
        "Almost there, hold steady": "اقتربت، اثبت", "Getting closer, keep turning": "تقترب، واصل الدوران", "Rotate until the Kaaba reaches the top": "دُر حتى تصل الكعبة إلى الأعلى",
        "This device has no compass. Turn on preview mode in Settings.": "هذا الجهاز بلا بوصلة. فعّل وضع المعاينة من الإعدادات.",
        "Location access is off. Turn it on in Settings so the compass can point to true north.": "الوصول للموقع مغلق. فعّله من الإعدادات لتشير البوصلة إلى الشمال الحقيقي.",
        "Starting the compass…": "جارٍ تشغيل البوصلة…", "Compass needs calibration. Move your phone in a figure of eight.": "البوصلة تحتاج إلى معايرة. حرّك هاتفك على شكل رقم ٨.",
        "Showing magnetic north. Allow location for true north.": "يتم عرض الشمال المغناطيسي. اسمح بالموقع للشمال الحقيقي.",
        // welcome
        "Find the Qibla, wherever you are": "اعرف القبلة أينما كنت", "Your location is used to work out the Qibla, your prayer times, nearby mosques and the weather.": "يُستخدم موقعك لحساب القبلة ومواقيت الصلاة والبحث عن المساجد القريبة والطقس.",
        "Calculated on your phone": "تُحسب على هاتفك", "Qibla and prayer times need no server": "القبلة ومواقيت الصلاة لا تحتاج إلى خادم",
        "No account needed": "لا حاجة لحساب", "No sign-up, no tracking, no ads": "بلا تسجيل ولا تتبع ولا إعلانات",
        "Works offline": "يعمل دون إنترنت", "Qibla and prayer times, anywhere": "القبلة ومواقيت الصلاة في أي مكان",
        "Allow location while using the app": "السماح بالموقع أثناء استخدام التطبيق", "Choose a city instead": "اختر مدينة بدلًا من ذلك",
        // azkhar
        "Quran: Tanzil · Adhkar: Hisn al-Muslim": "القرآن: تنزيل · الأذكار: حصن المسلم",
    ]
}

func L(_ s: String) -> String {
    let id = Loc.langID
    return Loc.ar ? (Loc.map[s] ?? LocNew.ui["ar"]?[s] ?? s) : (LocX.ui[id]?[s] ?? LocNew.ui[id]?[s] ?? s)
}
