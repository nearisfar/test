#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut
SetWorkingDir A_ScriptDir

; Global variables
global warningGui := ""
global countDown := 10
global prayerTimes := Map()
global sunnahTimes := Map()
global prayerDuration := 15
global settingsGui := ""
global statusBar := ""
global lastJsonResponse := ""
global isMonitoring := false
global initialGuiHeight := 600  ; Base GUI height
global minGuiHeight := 600      ; Minimum GUI height

; GUI Colors
global COLORS := {
    background: "FFFFFF",
    primary: "2196F3",
    secondary: "4CAF50",
    accent: "FF5722",
    text: "333333",
    textLight: "FFFFFF",
    warning: "F44336",
    success: "4CAF50",
    waiting: "FFA500",  ; Orange for waiting status
    border: "E0E0E0"
}

; Basic utility functions
TimeToMinutes(timeStr) {
    try {
        timeParts := StrSplit(timeStr, ":")
        return Integer(timeParts[1]) * 60 + Integer(timeParts[2])
    } catch {
        return 0
    }
}

IsValidTime(hour, minute) {
    try {
        hour := Integer(hour)
        minute := Integer(minute)
        return (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59)
    } catch {
        return false
    }
}

IsTimeInRange(current, start, end) {
    if (end >= 1440) {
        end := end - 1440
        return (start <= current || current < end)
    }
    return (start <= current && current < end)
}

; Prayer time core functions
RefreshPrayerTimes(*) {
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        city := settingsGui["City"].Text
        country := settingsGui["Country"].Text
        date := FormatTime(A_Now, "yyyy-MM-dd")
        
        url := "http://api.aladhan.com/v1/timingsByCity/" date "?city=" city "&country=" country "&method=2"
        
        http.Open("GET", url, true)
        http.Send()
        http.WaitForResponse()
        
        response := http.ResponseText
        lastJsonResponse := response
        
        if RegExMatch(response, '"Fajr":"([^"]+)".+?"Dhuhr":"([^"]+)".+?"Asr":"([^"]+)".+?"Maghrib":"([^"]+)".+?"Isha":"([^"]+)"', &times) {
            prayerTimes.Clear()  ; Clear existing times
            prayerTimes["Fajr"] := times[1]
            prayerTimes["Dhuhr"] := times[2]
            prayerTimes["Asr"] := times[3]
            prayerTimes["Maghrib"] := times[4]
            prayerTimes["Isha"] := times[5]
            
            UpdatePrayerTimesDisplay()
            statusBar.Text := "Prayer times updated successfully"
            return true
        }
        throw Error("Invalid response format")
    } catch as err {
        statusBar.Text := "Error: " err.Message
        SetTimer () => RefreshPrayerTimes(), -5000
        return false
    }
}

; Sunnah Prayer Management
AddSunnahTime(*) {
    prayerName := settingsGui["SunnahName"].Text
    hourText := settingsGui["SunnahHour"].Text
    minuteText := settingsGui["SunnahMinute"].Text
    
    if (prayerName = "") {
        MsgBox("Please enter a prayer name.", "Missing Name", "48")
        return
    }
    
    if (!IsValidTime(hourText, minuteText)) {
        MsgBox("Please enter valid time (Hour: 0-23, Minute: 0-59)", "Invalid Time", "48")
        return
    }
    
    hour := Integer(hourText)
    minute := Integer(minuteText)
    time := Format("{:02d}:{:02d}", hour, minute)
    
    if (sunnahTimes.Has(time)) {
        MsgBox("This time already exists!", "Duplicate Time", "48")
        return
    }
    
    sunnahTimes[time] := Map("name", prayerName, "time", time)
    UpdatePrayerTimesDisplay()
    
    ; Clear input fields
    settingsGui["SunnahName"].Text := ""
    settingsGui["SunnahHour"].Text := ""
    settingsGui["SunnahMinute"].Text := ""
}

DeleteSunnahTime(*) {
    selectedName := settingsGui["SunnahName"].Text
    if (selectedName = "") {
        MsgBox("Please enter the name of the prayer to delete.", "No Selection", "48")
        return
    }
    
    deleted := false
    for time, data in sunnahTimes {
        if (data["name"] = selectedName) {
            sunnahTimes.Delete(time)
            deleted := true
            break
        }
    }
    
    if (!deleted) {
        MsgBox("Prayer not found.", "Error", "48")
        return
    }
    
    UpdatePrayerTimesDisplay()
    settingsGui["SunnahName"].Text := ""
}

; GUI Update functions
UpdatePrayerTimesDisplay() {
    currentTime := FormatTime(A_Now, "HH:mm")
    currentMinutes := TimeToMinutes(currentTime)
    
    ; Update Wajib prayers
    for prayerName, time in prayerTimes {
        settingsGui[prayerName].Text := time
        timeStatus := GetPrayerTimeStatus(currentMinutes, TimeToMinutes(time))
        
        ; Update status with colored background
        statusCtrl := settingsGui[prayerName "Status"]
        bgColor := timeStatus = "Active" ? COLORS.warning :
                  timeStatus = "Next" ? COLORS.success :
                  COLORS.waiting
                  
        statusCtrl.Text := timeStatus
        statusCtrl.Opt("Background0x" bgColor)
        statusCtrl.Opt("c0x" COLORS.textLight)  ; White text for better contrast
    }
    
    ; Update Sunnah prayers
    yPos := settingsGui["SunnahStartPos"].Value
    baseYPos := yPos  ; Store initial position for calculating final height
    
    ; Clear existing Sunnah prayer displays
    for ctrl in settingsGui {
        if (InStr(ctrl.Name, "Sunnah_") = 1) {
            ctrl.Delete()  ; Changed from Destroy to Delete
        }
    }
    
    ; Sort Sunnah prayers by time
    sortedTimes := []
    for time, data in sunnahTimes {
        sortedTimes.Push({time: time, data: data})
    }
    
    ; Manual sorting of the array
    if (sortedTimes.Length > 0) {
        Loop sortedTimes.Length - 1 {
            i := A_Index
            Loop sortedTimes.Length - i {
                j := A_Index + i
                if (TimeToMinutes(sortedTimes[A_Index].time) > TimeToMinutes(sortedTimes[j].time)) {
                    temp := sortedTimes[A_Index]
                    sortedTimes[A_Index] := sortedTimes[j]
                    sortedTimes[j] := temp
                }
            }
        }
    }
    
    ; Add sorted Sunnah prayers to display
    for entry in sortedTimes {
        time := entry.time
        data := entry.data
        timeStatus := GetPrayerTimeStatus(currentMinutes, TimeToMinutes(time))
        
        ; Create prayer name
        settingsGui.Add("Text", "x20 y" yPos " w150 vSunnah_Name_" time, data["name"])
        
        ; Create time display
        settingsGui.Add("Text", "x180 y" yPos " w90 vSunnah_Time_" time, time)
        
        ; Create status with background color
        bgColor := timeStatus = "Active" ? COLORS.warning :
                  timeStatus = "Next" ? COLORS.success :
                  COLORS.waiting
                  
        statusCtrl := settingsGui.Add("Text", "x280 y" yPos " w130 Center Background0x" bgColor " c0x" COLORS.textLight " vSunnah_Status_" time, timeStatus)
        
        yPos += 30
    }
    
    ; Calculate and update GUI height if needed
    totalSunnahHeight := (sortedTimes.Length * 30) + 60  ; Height of all Sunnah prayers + padding
    newHeight := Max(initialGuiHeight, minGuiHeight + totalSunnahHeight)
    
    ; Move custom prayer controls and adjust GUI height
    if (settingsGui.HasProp("CustomPrayerGroup")) {
        settingsGui["CustomPrayerGroup"].Move(, yPos + 10)
        settingsGui["SettingsGroup"].Move(, yPos + 80)
        settingsGui["StatusBar"].Move(, yPos + 160)
        settingsGui.Move(,, newHeight)  ; Adjust GUI height
    }
    
    UpdateNextPrayer()
}

UpdateNextPrayer(*) {
    if (!settingsGui)
        return

    currentTime := FormatTime(A_Now, "HH:mm")
    currentMinutes := TimeToMinutes(currentTime)
    nextPrayer := "None"
    nextTime := ""
    minDiff := 24 * 60
    
    ; Check both Wajib and Sunnah prayers
    allPrayers := Map()
    for name, time in prayerTimes
        allPrayers[name] := time
    
    for time, data in sunnahTimes
        allPrayers[data["name"]] := time
    
    for prayerName, time in allPrayers {
        prayerMinutes := TimeToMinutes(time)
        diff := prayerMinutes - currentMinutes
        
        if (diff < 0)
            diff += 24 * 60
            
        if (diff < minDiff) {
            minDiff := diff
            nextPrayer := prayerName
            nextTime := time
        }
    }
    
    ; Format time until next prayer
    timeUntil := ""
    if (nextPrayer != "None") {
        hours := Floor(minDiff / 60)
        minutes := Mod(minDiff, 60)
        
        if (hours > 0)
            timeUntil .= hours " hour" (hours > 1 ? "s" : "") " "
        if (minutes > 0)
            timeUntil .= minutes " minute" (minutes > 1 ? "s" : "")
        else if (hours = 0)
            timeUntil := "less than 1 minute"
            
        settingsGui["NextPrayerDisplay"].Text := nextPrayer " in " timeUntil
        settingsGui["NextPrayerDisplay"].Opt("c0x" COLORS.text)  ; Set dark text color
    } else {
        settingsGui["NextPrayerDisplay"].Text := "No upcoming prayers"
    }
}

GetPrayerTimeStatus(currentMinutes, prayerMinutes) {
    if (IsWithinPrayerTime(currentMinutes, prayerMinutes))
        return "Active"
    if (IsNextPrayer(currentMinutes, prayerMinutes))
        return "Next"
    return "Waiting"
}

IsWithinPrayerTime(currentMinutes, startMinutes) {
    endMinutes := startMinutes + prayerDuration
    return IsTimeInRange(currentMinutes, startMinutes, endMinutes)
}

IsNextPrayer(currentMinutes, prayerMinutes) {
    if (prayerMinutes <= currentMinutes)
        return false
        
    for _, time in prayerTimes {
        otherMinutes := TimeToMinutes(time)
        if (otherMinutes > currentMinutes && otherMinutes < prayerMinutes)
            return false
    }
    return true
}

UpdateStatusBar(*) {
    if settingsGui {
        try {
            status := isMonitoring ? "Monitoring Active" : "Monitoring Inactive"
            statusBar.Text := status
        }
    }
}

UpdateHeaderTime(*) {
    if settingsGui {
        try settingsGui["HeaderTime"].Text := FormatTime(, "HH:mm:ss")
    }
}

MonitorSystem(*) {
    global warningGui
    static isLocked := false
    currentTime := FormatTime(A_Now, "HH:mm")
    currentMinutes := TimeToMinutes(currentTime)
    shouldBeLocked := false
    
    ; Check all prayer times
    allPrayers := Map()
    for name, time in prayerTimes
        allPrayers[name] := time
    
    for time, data in sunnahTimes
        allPrayers[data["name"]] := time
    
    for _, time in allPrayers {
        if (IsWithinPrayerTime(currentMinutes, TimeToMinutes(time))) {
            shouldBeLocked := true
            break
        }
    }
    
    if (shouldBeLocked) {
        if (!isLocked) {
            DllCall("LockWorkStation")
            isLocked := true
        } else if (!DllCall("GetSystemMetrics", "Int", 70)) {
            CreateWarningGui()
        }
    } else {
        isLocked := false
        if warningGui {
            try warningGui.Destroy()
            warningGui := ""
        }
    }
    
    UpdatePrayerTimesDisplay()
}

; GUI Creation and Management
CreateSettingsGui() {
    global settingsGui := Gui("+AlwaysOnTop -MinimizeBox")
    settingsGui.BackColor := "0x" COLORS.background
    settingsGui.SetFont("s10", "Segoe UI")
    settingsGui.Title := "Prayer Time Lock"

    ; Header
    headerHeight := 40
    AddHeader("x0 y0 w600 h" headerHeight)

    ; Next Prayer Box (with larger font)
    yPos := headerHeight + 10
    settingsGui.Add("GroupBox", "x10 y" yPos " w580 h70 Background0x" COLORS.primary)
    settingsGui.SetFont("s18 bold", "Segoe UI")  ; Large font for next prayer display
    settingsGui.Add("Text", "x20 y" (yPos+20) " w560 h35 vNextPrayerDisplay Center c0x" COLORS.textLight, "Loading next prayer time...")
    settingsGui.SetFont("s10", "Segoe UI")  ; Reset font

    ; Prayer Times Section
    yPos += 80
    settingsGui.Add("GroupBox", "x10 y" yPos " w580 h480", "Prayer Times")
    
    ; Headers
    yPos += 25
    settingsGui.SetFont("s10 bold", "Segoe UI")
    headers := ["Prayer", "Time", "Status"]
    xPositions := [20, 180, 280]
    widths := [150, 90, 130]
    
    Loop headers.Length {
        settingsGui.Add("Text", "x" xPositions[A_Index] " y" yPos " w" widths[A_Index], headers[A_Index])
    }
    
    ; Separator
    yPos += 25
    settingsGui.Add("Progress", "x20 y" yPos " w550 h2 Background0x" COLORS.border)

    ; Wajib Prayers
    yPos += 10
    settingsGui.SetFont("s10 bold c0x" COLORS.primary)
    settingsGui.Add("Text", "x20 y" yPos " w550", "Sholat Wajib")
    
    ; Prayer Times List
    settingsGui.SetFont("s10 norm c0x" COLORS.text)
    prayers := ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    yPos += 30
    
    For prayer in prayers {
        settingsGui.Add("Text", "x" xPositions[1] " y" yPos " w" widths[1], prayer)
        settingsGui.Add("Text", "v" prayer " x" xPositions[2] " y" yPos " w" widths[2], "Loading...")
        settingsGui.Add("Text", "v" prayer "Status x" xPositions[3] " y" yPos " w" widths[3] " Center", "Waiting")
        yPos += 30
    }

    ; Sunnah Section
    yPos += 10
    settingsGui.SetFont("s10 bold c0x" COLORS.primary)
    settingsGui.Add("Text", "x20 y" yPos " w550", "Sholat Sunnah")
    
    ; Store the starting position for Sunnah prayers (hidden)
    settingsGui.AddText("vSunnahStartPos Hidden", yPos + 30)

    ; Add Custom Prayer Group
    yPos += 40
    settingsGui.Add("GroupBox", "x20 y" yPos " w550 h60 vCustomPrayerGroup", "Add Custom Prayer")
    
    controlsY := yPos + 25
    settingsGui.Add("Text", "x30 y" controlsY+3, "Name:")
    settingsGui.Add("Edit", "vSunnahName x80 y" controlsY " w120")
    settingsGui.Add("Text", "x210 y" controlsY+3, "Time:")
    settingsGui.Add("Edit", "vSunnahHour x250 y" controlsY " w40 Number", "")
    settingsGui.Add("Text", "x295 y" controlsY+3, ":")
    settingsGui.Add("Edit", "vSunnahMinute x310 y" controlsY " w40 Number", "")
    AddStyledButton("Add", "x360 y" controlsY " w60")
    AddStyledButton("Delete", "x430 y" controlsY " w60")

    ; Settings Section
    yPos += 70
    settingsGui.Add("GroupBox", "x20 y" yPos " w550 h60 vSettingsGroup", "Settings")
    controlsY := yPos + 25
    settingsGui.Add("Text", "x30 y" controlsY+3, "City:")
    settingsGui.Add("Edit", "vCity x70 y" controlsY " w120", "Jakarta")
    settingsGui.Add("Text", "x200 y" controlsY+3, "Country:")
    settingsGui.Add("Edit", "vCountry x260 y" controlsY " w120", "Indonesia")
    settingsGui.Add("Text", "x390 y" controlsY+3, "Duration:")
    settingsGui.Add("Edit", "vPrayerDuration x460 y" controlsY " w50 Number", "15")
    settingsGui.Add("Text", "x515 y" controlsY+3, "min")

    ; Control Buttons
    yPos += 70
    AddStyledButton("Start", "x20 y" yPos " w100 h30")
    AddStyledButton("Refresh", "x130 y" yPos " w100 h30")

    ; Status Bar
    global statusBar := settingsGui.Add("Text", "x10 y" (yPos + 40) " w580 h20 vStatusBar", "Ready")
    
    ; Event Handlers
    settingsGui["Start"].OnEvent("Click", StartMonitoring)
    settingsGui["Refresh"].OnEvent("Click", RefreshPrayerTimes)
    settingsGui["Add"].OnEvent("Click", AddSunnahTime)
    settingsGui["Delete"].OnEvent("Click", DeleteSunnahTime)
    settingsGui.OnEvent("Close", (*) => ExitApp())

    ; Initialize timers
    SetTimer(UpdateHeaderTime, 1000)
    SetTimer(UpdateStatusBar, 1000)
    SetTimer(UpdateNextPrayer, 1000)  ; Update next prayer display every second

    ; Show GUI and start
    settingsGui.Show("w600 h" initialGuiHeight)
    RefreshPrayerTimes()
}

; Helper GUI Functions
AddHeader(options) {
    header := settingsGui.Add("Progress", options " Background0x" COLORS.primary)
    settingsGui.SetFont("s10 bold", "Segoe UI")
    settingsGui.Add("Text", "x10 y8 c0x" COLORS.textLight, FormatTime(, "dddd, MMMM d, yyyy"))
    settingsGui.Add("Text", "vHeaderTime x450 y8 c0x" COLORS.textLight, FormatTime(, "HH:mm:ss"))
}

AddStyledButton(name, options) {
    btn := settingsGui.Add("Button", "v" name " " options, name)
    btn.SetFont("s10", "Segoe UI")
}

StartMonitoring(*) {
    global isMonitoring
    
    if (settingsGui["Start"].Text = "Start") {
        try {
            global prayerDuration := Integer(settingsGui["PrayerDuration"].Text)
            if (prayerDuration < 1 || prayerDuration > 60)
                throw Error("Invalid duration")
        } catch {
            MsgBox("Prayer duration must be between 1 and 60 minutes.", "Invalid Duration", "48")
            return
        }
        
        settingsGui["Start"].Text := "Stop"
        isMonitoring := true
        SetTimer(MonitorSystem, 1000)
    } else {
        settingsGui["Start"].Text := "Start"
        isMonitoring := false
        SetTimer(MonitorSystem, 0)
    }
    
    UpdateStatusBar()
}

CreateWarningGui() {
    global warningGui, countDown
    
    if warningGui {
        try warningGui.Destroy()
    }
    
    countDown := 10
    warningGui := Gui("+AlwaysOnTop +ToolWindow -SysMenu -Caption")
    warningGui.BackColor := "0x" COLORS.background
    warningGui.SetFont("s12", "Segoe UI")
    
    screenWidth := A_ScreenWidth
    screenHeight := A_ScreenHeight
    guiWidth := 400
    guiHeight := 150
    xPos := (screenWidth - guiWidth) / 2
    yPos := (screenHeight - guiHeight) / 2
    
    warningGui.Add("Text", "x10 y10 w380 Center c0x" COLORS.warning, "Prayer Time Active")
    warningGui.Add("Text", "x10 y40 w380 Center", "Please complete your prayer before using the computer.")
    warningGui.Add("Text", "vCountdownText x10 y70 w380 Center", "System will lock in " countDown " seconds")
    warningGui.Add("Progress", "vProgressBar x10 y100 w380 h30 Range0-10 c0x" COLORS.primary, countDown)
    
    warningGui.Show("w" guiWidth " h" guiHeight " x" xPos " y" yPos)
    SetTimer(UpdateCountdown, 1000)
}

UpdateCountdown(*) {
    global countDown, warningGui
    if (!warningGui || !countDown)
        return
        
    countDown -= 1
    warningGui["CountdownText"].Text := "System will lock in " countDown " seconds"
    warningGui["ProgressBar"].Value := countDown
    
    if (countDown <= 0) {
        SetTimer(UpdateCountdown, 0)
        DllCall("LockWorkStation")
        warningGui.Destroy()
        warningGui := ""
    }
}

; Initialize
; Create tray menu
A_TrayMenu.Delete
A_TrayMenu.Add("Show Settings", (*) => settingsGui.Show())
A_TrayMenu.Add("Refresh Times", (*) => RefreshPrayerTimes())
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())

; Start the application
CreateSettingsGui()