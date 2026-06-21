-- ============================================================
-- Syu_uhub PC限定版 v3.1
-- 右クリック長押しで近くのプレイヤーをロック
-- 円形範囲内のプレイヤーをヘッドロック/近接部位ロック
-- Rayfield UI を使用 (エラーハンドリング追加)
-- ============================================================

-- Rayfield を安全にロード
local success, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if not success or not Rayfield then
    warn("Rayfield のロードに失敗しました。インターネット接続を確認してください。")
    -- 代替として簡単な通知を表示（任意）
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "エラー",
        Text = "Rayfield の読み込みに失敗しました。",
        Duration = 5
    })
    return -- スクリプト停止
end

-- サービス
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================================
-- 設定値
-- ============================================================
local Settings = {
    LockEnabled = false,
    LockRange = 15,              -- ロック範囲（スタッド）
    CircleSize = 150,            -- 円のサイズ（ピクセル）
    LockMode = "Head",           -- "Head" or "Closest"
    CircleEnabled = true,
    CircleColor = Color3.fromRGB(255, 50, 50),
    CircleTransparency = 0.5,
    SmoothLockEnabled = true,
    SmoothLockSpeed = 0.15,
    HoldTime = 0.3,              -- 長押し判定時間（秒）
    ShowIndicator = true,
}

-- ============================================================
-- 状態管理
-- ============================================================
local isLocking = false
local currentTarget = nil
local lockConnection = nil
local mouseDownTime = 0
local isMouseDown = false
local lockStartTime = 0

-- 円描画用
local CircleGui = nil
local CircleFrame = nil

-- ロックインジケーター
local LockIndicator = nil

-- ============================================================
-- ロックインジケーター作成
-- ============================================================
local function CreateLockIndicator()
    if LockIndicator then pcall(function() LockIndicator:Destroy() end) end
    LockIndicator = Instance.new("BillboardGui")
    LockIndicator.Name = "LockIndicator"
    LockIndicator.AlwaysOnTop = true
    LockIndicator.Size = UDim2.new(4, 0, 4, 0)
    LockIndicator.StudsOffset = Vector3.new(0, 3, 0)
    LockIndicator.Enabled = false
    LockIndicator.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    local frame = Instance.new("Frame", LockIndicator)
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    local corner = Instance.new("UICorner", frame)
    corner.CornerRadius = UDim.new(0, 8)
    
    -- 外側のリング
    local ring = Instance.new("Frame", LockIndicator)
    ring.Size = UDim2.new(1.5, 0, 1.5, 0)
    ring.Position = UDim2.new(-0.25, 0, -0.25, 0)
    ring.BackgroundTransparency = 1
    ring.BorderSizePixel = 2
    ring.BorderColor3 = Color3.fromRGB(255, 50, 50)
    local ringCorner = Instance.new("UICorner", ring)
    ringCorner.CornerRadius = UDim.new(0, 8)
end

-- ============================================================
-- 円のGUI作成（画面上にオーバーレイ表示）
-- ============================================================
local function CreateCircle()
    if CircleGui then CircleGui:Destroy() end
    
    CircleGui = Instance.new("ScreenGui")
    CircleGui.Name = "SyuHub_Circle"
    CircleGui.Parent = CoreGui
    CircleGui.ResetOnSpawn = false
    CircleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    CircleFrame = Instance.new("Frame")
    CircleFrame.Size = UDim2.new(0, Settings.CircleSize, 0, Settings.CircleSize)
    CircleFrame.Position = UDim2.new(0.5, -Settings.CircleSize/2, 0.5, -Settings.CircleSize/2)
    CircleFrame.BackgroundTransparency = Settings.CircleTransparency
    CircleFrame.BackgroundColor3 = Settings.CircleColor
    CircleFrame.BorderSizePixel = 2
    CircleFrame.BorderColor3 = Settings.CircleColor
    CircleFrame.Visible = Settings.CircleEnabled
    CircleFrame.Parent = CircleGui
    
    -- 円形にするためのコーナー
    local corner = Instance.new("UICorner", CircleFrame)
    corner.CornerRadius = UDim.new(1, 0)
    
    -- 内側の透明リング
    local inner = Instance.new("Frame")
    inner.Size = UDim2.new(0.9, 0, 0.9, 0)
    inner.Position = UDim2.new(0.05, 0, 0.05, 0)
    inner.BackgroundTransparency = 1
    inner.BorderSizePixel = 1
    inner.BorderColor3 = Settings.CircleColor
    inner.Parent = CircleFrame
    local innerCorner = Instance.new("UICorner", inner)
    innerCorner.CornerRadius = UDim.new(1, 0)
    
    -- 十字線（中心点）
    local crossH = Instance.new("Frame")
    crossH.Size = UDim2.new(0.6, 0, 0, 2)
    crossH.Position = UDim2.new(0.2, 0, 0.5, -1)
    crossH.BackgroundColor3 = Settings.CircleColor
    crossH.BackgroundTransparency = 0.5
    crossH.BorderSizePixel = 0
    crossH.Parent = CircleFrame
    
    local crossV = Instance.new("Frame")
    crossV.Size = UDim2.new(0, 2, 0.6, 0)
    crossV.Position = UDim2.new(0.5, -1, 0.2, 0)
    crossV.BackgroundColor3 = Settings.CircleColor
    crossV.BackgroundTransparency = 0.5
    crossV.BorderSizePixel = 0
    crossV.Parent = CircleFrame
end

-- ============================================================
-- 円の位置更新（マウス追従）
-- ============================================================
local function UpdateCirclePosition()
    if not CircleFrame then return end
    local mousePos = UserInputService:GetMouseLocation()
    local viewportSize = Camera.ViewportSize
    CircleFrame.Position = UDim2.new(
        0, mousePos.X - Settings.CircleSize/2,
        0, mousePos.Y - Settings.CircleSize/2
    )
end

-- ============================================================
-- 壁判定
-- ============================================================
local function HasWallBetween(startPos, endPos, excludeChar)
    local dir = (endPos - startPos).Unit
    local dist = (endPos - startPos).Magnitude
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeChar and {excludeChar} or {}
    params.IgnoreWater = true
    local result = workspace:Raycast(startPos, dir * dist, params)
    if result then
        local hit = result.Instance
        while hit and hit ~= workspace do
            if Players:GetPlayerFromCharacter(hit) then return false end
            if hit:IsA("Model") and hit:FindFirstChild("Humanoid") then return false end
            hit = hit.Parent
        end
        return true
    end
    return false
end

-- ============================================================
-- ターゲット取得（円内のプレイヤー）
-- ============================================================
local function GetTargetInCircle()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local localPos = LocalPlayer.Character.HumanoidRootPart.Position
    local localChar = LocalPlayer.Character
    local best = nil
    local bestDist = math.huge
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer 
            and player.Character 
            and player.Character:FindFirstChild("HumanoidRootPart")
            and player.Character:FindFirstChild("Head") then
            
            local hum = player.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                local dist = (localPos - player.Character.HumanoidRootPart.Position).Magnitude
                
                if dist <= Settings.LockRange then
                    -- 壁判定
                    local wallBlocked = HasWallBetween(
                        localPos, 
                        player.Character.Head.Position, 
                        localChar
                    )
                    if not wallBlocked then
                        if dist < bestDist then
                            bestDist = dist
                            best = player
                        end
                    end
                end
            end
        end
    end
    
    return best
end

-- ============================================================
-- ロック対象部位の取得
-- ============================================================
local function GetLockPart(target)
    if not target or not target.Character then return nil end
    
    if Settings.LockMode == "Head" then
        return target.Character:FindFirstChild("Head")
    else
        -- 近接部位モード: 各部位の中で最も近いものを選択
        local localPos = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not localPos then return nil end
        
        local parts = {
            "Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso",
            "LeftArm", "RightArm", "LeftLeg", "RightLeg"
        }
        
        local bestPart = nil
        local bestDist = math.huge
        
        for _, partName in ipairs(parts) do
            local part = target.Character:FindFirstChild(partName)
            if part then
                local dist = (localPos.Position - part.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestPart = part
                end
            end
        end
        
        return bestPart
    end
end

-- ============================================================
-- カメラ制御
-- ============================================================
local function AimAt(targetPos)
    if Settings.SmoothLockEnabled then
        local goal = CFrame.new(Camera.CFrame.Position, targetPos)
        Camera.CFrame = Camera.CFrame:Lerp(goal, math.clamp(Settings.SmoothLockSpeed, 0.01, 1))
    else
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetPos)
    end
end

-- ============================================================
-- ロック開始
-- ============================================================
local function StartLock()
    if isLocking then return end
    if not Settings.LockEnabled then return end
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    local target = GetTargetInCircle()
    if not target then return end
    
    currentTarget = target
    isLocking = true
    lockStartTime = tick()
    
    -- インジケーター表示
    if Settings.ShowIndicator and LockIndicator then
        local head = target.Character and target.Character:FindFirstChild("Head")
        if head then
            LockIndicator.Adornee = head
            LockIndicator.Enabled = true
        end
    end
    
    -- ロックループ開始
    if lockConnection then lockConnection:Disconnect() end
    lockConnection = RunService.RenderStepped:Connect(function()
        if not Settings.LockEnabled 
            or not isLocking 
            or not currentTarget 
            or not currentTarget.Character then
            StopLock()
            return
        end
        
        local localChar = LocalPlayer.Character
        if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then
            StopLock()
            return
        end
        
        -- 距離チェック
        local localPos = localChar.HumanoidRootPart.Position
        local targetPos = currentTarget.Character:FindFirstChild("HumanoidRootPart")
        if not targetPos then
            StopLock()
            return
        end
        
        local dist = (localPos - targetPos.Position).Magnitude
        if dist > Settings.LockRange then
            StopLock()
            return
        end
        
        -- 壁判定
        if HasWallBetween(localPos, currentTarget.Character.Head.Position, localChar) then
            StopLock()
            return
        end
        
        -- ロック部位を取得
        local lockPart = GetLockPart(currentTarget)
        if not lockPart then
            StopLock()
            return
        end
        
        -- カメラをロック部位に向ける
        AimAt(lockPart.Position)
    end)
end

-- ============================================================
-- ロック停止
-- ============================================================
local function StopLock()
    if lockConnection then
        lockConnection:Disconnect()
        lockConnection = nil
    end
    isLocking = false
    currentTarget = nil
    if LockIndicator then LockIndicator.Enabled = false end
end

-- ============================================================
-- リセット関数
-- ============================================================
local function ResetLock()
    StopLock()
end

-- ============================================================
-- プレイヤー参加/退出
-- ============================================================
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        if isLocking and currentTarget == player then
            StopLock()
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    if isLocking and currentTarget == player then
        StopLock()
    end
end)

-- ============================================================
-- マウス入力処理（PC用）
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- 右クリック（マウスボタン2）
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isMouseDown = true
        mouseDownTime = tick()
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isMouseDown = false
        mouseDownTime = 0
        -- マウスを離したらロック解除
        if isLocking then
            StopLock()
        end
    end
end)

-- 長押し判定（毎フレームチェック）
RunService.RenderStepped:Connect(function()
    if isMouseDown and Settings.LockEnabled then
        local holdTime = tick() - mouseDownTime
        if holdTime >= Settings.HoldTime and not isLocking then
            StartLock()
        end
    end
    
    -- 円の位置更新
    if Settings.CircleEnabled then
        UpdateCirclePosition()
    end
end)

-- ============================================================
-- キーボードショートカット
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.RightControl then
        Settings.LockEnabled = not Settings.LockEnabled
        if not Settings.LockEnabled then
            StopLock()
        end
    elseif input.KeyCode == Enum.KeyCode.RightShift then
        StopLock()
    end
end)

-- ============================================================
-- UI - メインタブ (Rayfield)
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name = "Syu_uhub PC",
    LoadingTitle = "Syu_uhub PC Loading...",
    LoadingSubtitle = "by Syu - Right Click Lock System",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "SyuHubPC",
        FileName = "SyuHubPCConfig"
    }
})

local MainTab = Window:CreateTab("メイン", 4483362458)
local SettingsTab = Window:CreateTab("設定", 4483345998)
local InfoTab = Window:CreateTab("情報", 4483345998)

-- ============================================================
-- メインタブ
-- ============================================================
MainTab:CreateToggle({
    Name = "🔐 右クリックロック",
    CurrentValue = false,
    Flag = "LockToggle",
    Callback = function(v)
        Settings.LockEnabled = v
        if not v then StopLock() end
    end,
})

MainTab:CreateParagraph({
    Title = "操作方法",
    Content = "・右クリックを長押し（0.3秒）で近くのプレイヤーをロック\n・右クリックを離すとロック解除\n・RightCtrl: ロックON/OFF\n・RightShift: ロックリセット"
})

MainTab:CreateButton({
    Name = "🔄 ロックリセット",
    Callback = function()
        StopLock()
    end,
})

MainTab:CreateSection("🎯 ロックモード")
MainTab:CreateDropdown({
    Name = "ロック部位",
    Options = {"頭 (Head)", "近接部位"},
    CurrentOption = {"頭 (Head)"},
    Flag = "LockModeDropdown",
    Callback = function(Option)
        Settings.LockMode = Option[1] == "頭 (Head)" and "Head" or "Closest"
    end,
})

MainTab:CreateSection("⭕ 円表示")
MainTab:CreateToggle({
    Name = "円を表示",
    CurrentValue = true,
    Flag = "CircleToggle",
    Callback = function(v)
        Settings.CircleEnabled = v
        if CircleFrame then CircleFrame.Visible = v end
    end,
})

-- ============================================================
-- 設定タブ
-- ============================================================
SettingsTab:CreateSection("📏 ロック範囲設定")
SettingsTab:CreateSlider({
    Name = "ロック範囲（スタッド）",
    Range = {5, 30},
    Increment = 0.5,
    CurrentValue = 15,
    Flag = "LockRangeSlider",
    Callback = function(v)
        Settings.LockRange = v
    end,
})

SettingsTab:CreateSlider({
    Name = "円のサイズ（ピクセル）",
    Range = {80, 400},
    Increment = 5,
    CurrentValue = 150,
    Flag = "CircleSizeSlider",
    Callback = function(v)
        Settings.CircleSize = v
        if CircleFrame then
            CircleFrame.Size = UDim2.new(0, v, 0, v)
            -- 位置はマウス追従で更新されるため、ここでは設定しない
        end
    end,
})

SettingsTab:CreateSection("🎨 円の色設定")
SettingsTab:CreateColorPicker({
    Name = "円の色",
    Color = Settings.CircleColor,
    Flag = "CircleColorPicker",
    Callback = function(v)
        Settings.CircleColor = v
        if CircleFrame then
            CircleFrame.BackgroundColor3 = v
            CircleFrame.BorderColor3 = v
            -- 内側のリングの色も更新
            for _, child in ipairs(CircleFrame:GetChildren()) do
                if child:IsA("Frame") and child ~= CircleFrame then
                    if child.BorderColor3 then child.BorderColor3 = v end
                    if child.BackgroundColor3 then child.BackgroundColor3 = v end
                end
            end
        end
    end,
})

SettingsTab:CreateSlider({
    Name = "円の透明度",
    Range = {0, 1},
    Increment = 0.05,
    CurrentValue = 0.5,
    Flag = "CircleTransparencySlider",
    Callback = function(v)
        Settings.CircleTransparency = v
        if CircleFrame then
            CircleFrame.BackgroundTransparency = v
        end
    end,
})

SettingsTab:CreateSection("🎮 ロック設定")
SettingsTab:CreateToggle({
    Name = "🌀 スムーズロック",
    CurrentValue = true,
    Flag = "SmoothLockToggle",
    Callback = function(v)
        Settings.SmoothLockEnabled = v
    end,
})

SettingsTab:CreateSlider({
    Name = "スムーズ速度",
    Range = {0.01, 0.5},
    Increment = 0.01,
    CurrentValue = 0.15,
    Flag = "SmoothLockSpeedSlider",
    Callback = function(v)
        Settings.SmoothLockSpeed = v
    end,
})

SettingsTab:CreateSlider({
    Name = "長押し判定時間（秒）",
    Range = {0.1, 1},
    Increment = 0.05,
    CurrentValue = 0.3,
    Flag = "HoldTimeSlider",
    Callback = function(v)
        Settings.HoldTime = v
    end,
})

SettingsTab:CreateToggle({
    Name = "ロックインジケーター",
    CurrentValue = true,
    Flag = "IndicatorToggle",
    Callback = function(v)
        Settings.ShowIndicator = v
        if not v and LockIndicator then
            LockIndicator.Enabled = false
        end
    end,
})

-- ============================================================
-- 情報タブ
-- ============================================================
InfoTab:CreateSection("📊 現在の状態")

local lblStatus = InfoTab:CreateLabel("状態: 待機中")
local lblTarget = InfoTab:CreateLabel("ターゲット: なし")
local lblRange = InfoTab:CreateLabel("ロック範囲: " .. Settings.LockRange .. " スタッド")
local lblMode = InfoTab:CreateLabel("ロックモード: " .. (Settings.LockMode == "Head" and "頭" or "近接部位"))

InfoTab:CreateButton({
    Name = "🔄 状態を更新",
    Callback = function()
        if isLocking and currentTarget then
            lblStatus:SetText("状態: 🔒 ロック中")
            lblTarget:SetText("ターゲット: " .. currentTarget.Name)
        else
            lblStatus:SetText("状態: 🔓 待機中")
            lblTarget:SetText("ターゲット: なし")
        end
        lblRange:SetText("ロック範囲: " .. Settings.LockRange .. " スタッド")
        lblMode:SetText("ロックモード: " .. (Settings.LockMode == "Head" and "頭" or "近接部位"))
    end,
})

InfoTab:CreateSection("ℹ️ 説明")
InfoTab:CreateParagraph({
    Title = "使い方",
    Content = "1. 設定タブでロック範囲（5〜30スタッド）を設定\n2. メインタブで「右クリックロック」をON\n3. ゲーム内で右クリックを長押し（0.3秒）\n4. 円内にいる最も近いプレイヤーを自動ロック\n5. 右クリックを離すとロック解除"
})

InfoTab:CreateParagraph({
    Title = "ロックモード",
    Content = "・頭 (Head): プレイヤーの頭部をロック\n・近接部位: 最も近い体の部位をロック（頭・体・腕・脚から選択）"
})

-- ============================================================
-- 初期化
-- ============================================================
task.spawn(function()
    task.wait(1)
    CreateLockIndicator()
    CreateCircle()
    if CircleFrame then
        CircleFrame.Visible = Settings.CircleEnabled
    end
end)

Rayfield:LoadConfiguration()

-- ============================================================
-- クリーンアップ
-- ============================================================
local function Cleanup()
    StopLock()
    if LockIndicator then pcall(function() LockIndicator:Destroy() end) end
    if CircleGui then pcall(function() CircleGui:Destroy() end) end
end

game:BindToClose(Cleanup)
game:GetService("CoreGui").ChildRemoved:Connect(function(child)
    if child.Name == "Rayfield" then Cleanup() end
end)
