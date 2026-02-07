FUNCTION_BLOCK FB_Pump
VAR_INPUT
    // Команды от оператора
    Start: BOOL;             // Кнопка "Пуск" 
   Stop: BOOL;              // Кнопка "Стоп" 
    bAutoMode: BOOL;          // TRUE = Автоматический режим, FALSE = Ручной
    
    // Сигналы от оборудования
    bThermalOK: BOOL;         // Тепловое реле (1 = норма, 0 = авария)
    rPressure: REAL;          // Текущее давление из датчика (бар)
    
    // Уставки
    rSetLow: REAL := 3.5;     // P_min - давление включения (бар)
    rSetHigh: REAL := 5.0;    // P_max - давление выключения (бар)
    rAlarmLow: REAL := 2.0;   // Аварийное низкое давление (бар)
    rAlarmHigh: REAL := 6.5;  // Аварийное высокое давление (бар)
    
    // Команды сброса
    bResetAlarm: BOOL;        // Сброс аварий
    bResetHours: BOOL;        // Сброс счетчика моточасов
    
    // Настройки
    tStartDelay: TIME := T#2S;    // Задержка перед пуском
    tMinRunTime: TIME := T#10S;   // Минимальное время работы
    tMinStopTime: TIME := T#30S;  // Минимальное время простоя
END_VAR

VAR_OUTPUT
    bRun: BOOL;               // Команда на пускатель насоса (1 = ВКЛ)
    bRunning: BOOL;           // Статус насос работает
    bAutoActive: BOOL;        // Автоматический режим
    
    // Аварии и предупреждения
    bAlarmThermal: BOOL;      // Авария тепловой защиты
    bAlarmPressure: BOOL;     // Авария по давлению
        
    // Диагностика
    rRuntimeHours: REAL;      // Наработка в часах
    iStartCount: UINT;        // Количество пусков
    
    // Технологические статусы
    bPressureLow: BOOL;       // Давление ниже P_min
    bPressureHigh: BOOL;      // Давление выше P_max
    bPressureOK: BOOL;        // Давление в рабочем диапазоне
    
    // Блокировки
    bPermissive: BOOL;        // Общее разрешение на работу
    StartBlock: BOOL;        // Пуск заблокирован
   StopBlock: BOOL;         // Останов заблокирован
END_VAR

VAR
    // Внутренние переменные
    StartCmd: BOOL;         // команда пуска
   StopCmd: BOOL;           // команда останова
    bAutoStart: BOOL;         // Команда пуска от автоматики
    bAutoStop: BOOL;          // Команда останова от автоматики
    
    // Триггеры
    ffStart: SR;              // Триггер для команды пуска
    ffAlarm: SR;              // Триггер для аварии
    
    // Таймеры
    tStartDelay: TON;         // Таймер задержки пуска
    tMinRun: TON;             // Таймер минимального времени работы
    tMinStop: TON;            // Таймер минимального времени простоя
    
    // Счетчики
    iRuntimeSec: UDINT;       // Счетчик времени работы (сек)
    tCountSec: TON;           // Таймер для подсчета секунд
    
    // Флаги состояния
    bInternalRun: BOOL;       // Внутренний статус работы
    bFirstScan: BOOL := TRUE; // Флаг первого скана
    bPrevRun: BOOL;           // Предыдущее состояние работы
END_VAR

// 1. ИНИЦИАЛИЗАЦИЯ
IF bFirstScan THEN
    bFirstScan := FALSE;
    bInternalRun := FALSE;
    iRuntimeSec := 0;
    iStartCount := 0;
END_IF;

// 2. ОБРАБОТКА КНОПОК (триггеры)
// Триггер кнопки Пуск (сброс по Стоп или аварии)
ffStart(S := Start, R1 :=Stop OR bAlarmAny);
StartCmd := ffStart.Q1;

// Триггер кнопки Стоп (мгновенное действие)
IFStop THEN
   StopCmd := TRUE;
ELSE
   StopCmd := FALSE;
END_IF;


//ПРОВЕРКА АВАРИЙ
// Проверка теплового реле
bAlarmThermal := NOT bThermalOK;

// Проверка давления
bAlarmPressure := (rPressure < rAlarmLow) OR (rPressure > rAlarmHigh);

// Общая авария
bAlarmAny := bAlarmThermal OR bAlarmPressure;

// Триггер аварии (сброс кнопкой)
ffAlarm(S := bAlarmAny, R1 := bResetAlarm);

// Общее разрешение на работу
bPermissive := NOT ffAlarm.Q1;

// 4. ЛОГИКА УПРАВЛЕНИЯ ДАВЛЕНИЕМ
// Определение состояния давления
bPressureLow := (rPressure <= rSetLow);
bPressureHigh := (rPressure >= rSetHigh);
bPressureOK := (rPressure > rSetLow) AND (rPressure < rSetHigh);

// Автоматическое управление
IF bAutoMode AND bPermissive THEN
    // Включение при низком давлении
    IF bPressureLow AND NOT bInternalRun THEN
        bAutoStart := TRUE;
        bAutoStop := FALSE;
    // Выключение при высоком давлении
    ELSIF bPressureHigh AND bInternalRun THEN
        bAutoStart := FALSE;
        bAutoStop := TRUE;
    // Сохранение состояния
    ELSE
        bAutoStart := bAutoStart;
        bAutoStop := bAutoStop;
    END_IF;
ELSE
    bAutoStart := FALSE;
    bAutoStop := FALSE;
END_IF;

// Статус автоматического режима
bAutoActive := bAutoMode AND bPermissive;


// 5. ЗАЩИТА ОТ ЧАСТЫХ ПУСКОВ
// Таймеры минимального времени
tMinRun(IN := bInternalRun, PT := tMinRunTime);
tMinStop(IN := NOT bInternalRun, PT := tMinStopTime);

// Блокировки
StartBlock := (bInternalRun AND NOT tMinRun.Q) OR 
               (NOT bInternalRun AND NOT tMinStop.Q);
bStopBlock := bInternalRun AND NOT tMinRun.Q;

// 6. ФОРМИРОВАНИЕ КОМАНДЫ ПУСКА

// ручной режим
IF (StartCmd OR bAutoStart) AND 
   bPermissive AND 
   NOT StartBlock AND
   NOT bAutoMode THEN
    tStartDelay(IN := TRUE, PT := tStartDelay);
ELSE
    tStartDelay(IN := FALSE, PT := tStartDelay);
END_IF;
// В автоматическом режиме пуск без задержки
IF bAutoStart AND bAutoMode AND bPermissive AND NOT StartBlock THEN
    bInternalRun := TRUE;
// Ручной режим с задержкой
ELSIF tStartDelay.Q AND NOT bInternalRun THEN
    bInternalRun := TRUE;
END_IF;

// КОМАНДА ОСТАНОВА
// Немедленный останов при аварии
IF bAlarmAny THEN
    bInternalRun := FALSE;
// Останов по команде
ELSIF (bStopCmd OR bAutoStop) AND NOTStopBlock THEN
    bInternalRun := FALSE;
END_IF;

// 8. ВЫХОДНАЯ КОМАНДА И СТАТУС
bRun := bInternalRun AND bPermissive;
bRunning := bInternalRun;

// 9. СЧЕТЧИК МОТОЧАСОВ И ПУСКОВ
// Подсчет времени работы (1 сек интервал)
tCountSec(IN := bInternalRun, PT := T#1S);
IF tCountSec.Q THEN
    iRuntimeSec := iRuntimeSec + 1;
    rRuntimeHours := UDINT_TO_REAL(iRuntimeSec) / 3600.0;
END_IF;

// Счетчик пусков
IF bInternalRun AND NOT bPrevRun THEN
    iStartCount := iStartCount + 1;
END_IF;

// Сброс счетчиков
IF bResetHours THEN
    iRuntimeSec := 0;
    iStartCount := 0;
    rRuntimeHours := 0.0;
END_IF;


// 10. СОХРАНЕНИЕ СОСТОЯНИЯ
bPrevRun := bInternalRun;