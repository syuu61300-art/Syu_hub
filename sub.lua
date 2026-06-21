-- ============================================================
--  MobileAimLock.lua
--  LocalScript  →  StarterPlayerScripts に配置
--
--  【機能概要】
--  ・スマホ限定エイムアシスト（PC / コンソールは無効）
--  ・右サムスティック長押し（TouchLongPress）で
--    画面中央の「ロック円」内に入った最近傍プレイヤーの
--    頭 or 最近部位 をカメラでロック追跡
--  ・設定タブで スタッド距離(5〜30) と 円サイズ を変更可能
--  ・ロック中は半透明の追跡円 UI を表示
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera
local PlayerGui        = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
--  ▼ スマホ以外は完全スキップ
-- ============================================================
if not UserInputService.TouchEnabled
   or UserInputService.KeyboardEnabled
   or UserInputService.GamepadEnabled then
	warn("[MobileAimLock] スマホ以外では動作しません。スクリプトを停止します。")
	return
end

-- ============================================================
--  ▼ 設定（設定タブで動的に変更される）
-- ============================================================
local Settings = {
	studsRange    = 15,    -- ロック有効スタッド距離 (5〜30)
	circleRadius  = 120,   -- 画面上のロック円の半径（px）
	lockTarget    = "Head", -- "Head" or "Nearest"（近い部位）
	holdTime      = 0.15,  -- 長押し判定秒数
}

-- ============================================================
--  ▼ 状態
-- ============================================================
local locked        = false
local lockedPart    = nil   -- 追跡中のBasePart
local touchStart    = nil   -- 長押し開始時刻
local isHolding     = false
local settingsOpen  = false

-- ============================================================
--  ▼ UI 構築
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "AimLockGui"
ScreenGui.ResetOnSpawn   = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = PlayerGui

-- ── ロック円 ──
local CircleFrame = Instance.new("Frame")
CircleFrame.Name              = "LockCircle"
CircleFrame.AnchorPoint       = Vector2.new(0.5, 0.5)
CircleFrame.Position          = UDim2.new(0.5, 0, 0.5, 0)
CircleFrame.Size              = UDim2.new(
	0, Settings.circleRadius * 2,
	0, Settings.circleRadius * 2)
CircleFrame.BackgroundTransparency = 1
CircleFrame.BorderSizePixel   = 0
CircleFrame.Parent            = ScreenGui

local CircleStroke = Instance.new("UIStroke")
CircleStroke.Color     = Color3.fromRGB(255, 255, 255)
CircleStroke.Thickness = 2
CircleStroke.Transparency = 0.4
CircleStroke.Parent    = CircleFrame

local CircleCorner = Instance.new("UICorner")
CircleCorner.CornerRadius = UDim.new(1, 0)
CircleCorner.Parent       = CircleFrame

-- 塗りつぶし（薄い）
local CircleFill = Instance.new("Frame")
CircleFill.Name                   = "Fill"
CircleFill.Size                   = UDim2.fromScale(1, 1)
CircleFill.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
CircleFill.BackgroundTransparency = 0.92
CircleFill.BorderSizePixel        = 0
CircleFill.Parent                 = CircleFrame

local FillCorner = Instance.new("UICorner")
FillCorner.CornerRadius = UDim.new(1, 0)
FillCorner.Parent       = CircleFill

-- ロック状態インジケーター（円の色変化）
local function setCircleColor(color, fillAlpha)
	TweenService:Create(CircleStroke,
		TweenInfo.new(0.15), {Color = color}):Play()
	TweenService:Create(CircleFill,
		TweenInfo.new(0.15),
		{BackgroundColor3 = color,
		 BackgroundTransparency = fillAlpha}):Play()
end

-- ── ロック中テキスト ──
local LockLabel = Instance.new("TextLabel")
LockLabel.Name                 = "LockStatus"
LockLabel.AnchorPoint         = Vector2.new(0.5, 0)
LockLabel.Position            = UDim2.new(0.5, 0, 0.5,
	Settings.circleRadius + 8)
LockLabel.Size                = UDim2.new(0, 200, 0, 24)
LockLabel.BackgroundTransparency = 1
LockLabel.Font                = Enum.Font.GothamBold
LockLabel.TextSize            = 14
LockLabel.TextColor3          = Color3.fromRGB(255, 255, 255)
LockLabel.TextStrokeTransparency = 0.4
LockLabel.Text                = ""
LockLabel.Parent              = ScreenGui

-- ── 長押しゲージ（円の外枠が埋まる進行バー） ──
local HoldFrame = Instance.new("Frame")
HoldFrame.Name              = "HoldBar"
HoldFrame.AnchorPoint       = Vector2.new(0.5, 0.5)
HoldFrame.Position          = UDim2.new(0.5, 0, 0.5, 0)
HoldFrame.Size              = UDim2.new(
	0, Settings.circleRadius * 2 + 12,
	0, Settings.circleRadius * 2 + 12)
HoldFrame.BackgroundTransparency = 1
HoldFrame.Visible           = false
HoldFrame.Parent            = ScreenGui

local HoldArc = Instance.new("UIStroke")
HoldArc.Color       = Color3.fromRGB(255, 80, 80)
HoldArc.Thickness   = 4
HoldArc.Parent      = HoldFrame

local HoldCorner = Instance.new("UICorner")
HoldCorner.CornerRadius = UDim.new(1, 0)
HoldCorner.Parent       = HoldFrame

-- ============================================================
--  ▼ 設定タブ UI
-- ============================================================
-- 設定ボタン（歯車アイコン風）
local SettingsBtn = Instance.new("TextButton")
SettingsBtn.Name              = "SettingsBtn"
SettingsBtn.AnchorPoint       = Vector2.new(1, 0)
SettingsBtn.Position          = UDim2.new(1, -12, 0, 12)
SettingsBtn.Size              = UDim2.new(0, 44, 0, 44)
SettingsBtn.BackgroundColor3  = Color3.fromRGB(30, 30, 30)
SettingsBtn.BackgroundTransparency = 0.3
SettingsBtn.Text              = "⚙"
SettingsBtn.TextSize          = 24
SettingsBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
SettingsBtn.Font              = Enum.Font.GothamBold
SettingsBtn.BorderSizePixel   = 0
SettingsBtn.Parent            = ScreenGui

local SBCorner = Instance.new("UICorner")
SBCorner.CornerRadius = UDim.new(0, 10)
SBCorner.Parent       = SettingsBtn

-- 設定パネル
local SettingsPanel = Instance.new("Frame")
SettingsPanel.Name              = "SettingsPanel"
SettingsPanel.AnchorPoint       = Vector2.new(1, 0)
SettingsPanel.Position          = UDim2.new(1, -12, 0, 64)
SettingsPanel.Size              = UDim2.new(0, 260, 0, 320)
SettingsPanel.BackgroundColor3  = Color3.fromRGB(20, 20, 25)
SettingsPanel.BackgroundTransparency = 0.1
SettingsPanel.BorderSizePixel   = 0
SettingsPanel.Visible           = false
SettingsPanel.Parent            = ScreenGui

local PanelCorner = Instance.new("UICorner")
PanelCorner.CornerRadius = UDim.new(0, 14)
PanelCorner.Parent       = SettingsPanel

local PanelStroke = Instance.new("UIStroke")
PanelStroke.Color     = Color3.fromRGB(80, 80, 100)
PanelStroke.Thickness = 1.5
PanelStroke.Parent    = SettingsPanel

local PanelList = Instance.new("UIListLayout")
PanelList.FillDirection       = Enum.FillDirection.Vertical
PanelList.HorizontalAlignment = Enum.HorizontalAlignment.Center
PanelList.Padding             = UDim.new(0, 10)
PanelList.SortOrder           = Enum.SortOrder.LayoutOrder
PanelList.Parent              = SettingsPanel

local PanelPadding = Instance.new("UIPadding")
PanelPadding.PaddingTop    = UDim.new(0, 12)
PanelPadding.PaddingLeft   = UDim.new(0, 14)
PanelPadding.PaddingRight  = UDim.new(0, 14)
PanelPadding.PaddingBottom = UDim.new(0, 12)
PanelPadding.Parent        = SettingsPanel

-- ヘッダー
local PanelTitle = Instance.new("TextLabel")
PanelTitle.Size              = UDim2.new(1, 0, 0, 26)
PanelTitle.BackgroundTransparency = 1
PanelTitle.Text              = "🎯 AimLock 設定"
PanelTitle.Font              = Enum.Font.GothamBold
PanelTitle.TextSize          = 16
PanelTitle.TextColor3        = Color3.fromRGB(255, 255, 255)
PanelTitle.LayoutOrder       = 0
PanelTitle.Parent            = SettingsPanel

-- ── スライダー生成ユーティリティ ──
local function makeSlider(parent, label, min, max, default, layoutOrder, onChange)
	local container = Instance.new("Frame")
	container.Size              = UDim2.new(1, 0, 0, 58)
	container.BackgroundTransparency = 1
	container.LayoutOrder       = layoutOrder
	container.Parent            = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size              = UDim2.new(1, 0, 0, 18)
	nameLabel.Position          = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font              = Enum.Font.Gotham
	nameLabel.TextSize          = 13
	nameLabel.TextColor3        = Color3.fromRGB(200, 200, 210)
	nameLabel.TextXAlignment    = Enum.TextXAlignment.Left
	nameLabel.Text              = label
	nameLabel.Parent            = container

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size             = UDim2.new(0, 40, 0, 18)
	valueLabel.Position         = UDim2.new(1, -40, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font             = Enum.Font.GothamBold
	valueLabel.TextSize         = 13
	valueLabel.TextColor3       = Color3.fromRGB(255, 200, 80)
	valueLabel.TextXAlignment   = Enum.TextXAlignment.Right
	valueLabel.Text             = tostring(default)
	valueLabel.Parent           = container

	local track = Instance.new("Frame")
	track.Size                  = UDim2.new(1, 0, 0, 10)
	track.Position              = UDim2.new(0, 0, 0, 28)
	track.BackgroundColor3      = Color3.fromRGB(50, 50, 60)
	track.BorderSizePixel       = 0
	track.Parent                = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius    = UDim.new(1, 0)
	trackCorner.Parent          = track

	local fill = Instance.new("Frame")
	fill.Size                   = UDim2.new(
		(default - min) / (max - min), 0, 1, 0)
	fill.BackgroundColor3       = Color3.fromRGB(255, 80, 80)
	fill.BorderSizePixel        = 0
	fill.Parent                 = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius     = UDim.new(1, 0)
	fillCorner.Parent           = fill

	local knob = Instance.new("TextButton")
	knob.Size                   = UDim2.new(0, 22, 0, 22)
	knob.AnchorPoint            = Vector2.new(0.5, 0.5)
	knob.Position               = UDim2.new(
		(default - min) / (max - min), 0, 0.5, 0)
	knob.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	knob.Text                   = ""
	knob.BorderSizePixel        = 0
	knob.Parent                 = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius     = UDim.new(1, 0)
	knobCorner.Parent           = knob

	-- ドラッグ処理
	local dragging = false
	knob.TouchLongPress:Connect(function() end)  -- suppress default

	knob.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)

	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(inp)
		if dragging and inp.UserInputType == Enum.UserInputType.Touch then
			local trackPos  = track.AbsolutePosition
			local trackSize = track.AbsoluteSize
			local rx = math.clamp(
				(inp.Position.X - trackPos.X) / trackSize.X, 0, 1)
			local value = math.floor(min + rx * (max - min) + 0.5)
			fill.Size          = UDim2.new(rx, 0, 1, 0)
			knob.Position      = UDim2.new(rx, 0, 0.5, 0)
			valueLabel.Text    = tostring(value)
			onChange(value)
		end
	end)

	return container
end

-- ── セレクターボタン（頭 / 近い部位） ──
local function makeSelector(parent, layoutOrder)
	local frame = Instance.new("Frame")
	frame.Size              = UDim2.new(1, 0, 0, 54)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder       = layoutOrder
	frame.Parent            = parent

	local label = Instance.new("TextLabel")
	label.Size              = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Font              = Enum.Font.Gotham
	label.TextSize          = 13
	label.TextColor3        = Color3.fromRGB(200, 200, 210)
	label.TextXAlignment    = Enum.TextXAlignment.Left
	label.Text              = "ロック対象"
	label.Parent            = frame

	local btnHead = Instance.new("TextButton")
	btnHead.Size            = UDim2.new(0.48, 0, 0, 28)
	btnHead.Position        = UDim2.new(0, 0, 0, 24)
	btnHead.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	btnHead.Text            = "頭"
	btnHead.Font            = Enum.Font.GothamBold
	btnHead.TextSize        = 13
	btnHead.TextColor3      = Color3.fromRGB(255, 255, 255)
	btnHead.BorderSizePixel = 0
	btnHead.Parent          = frame

	local btnNearest = Instance.new("TextButton")
	btnNearest.Size         = UDim2.new(0.48, 0, 0, 28)
	btnNearest.Position     = UDim2.new(0.52, 0, 0, 24)
	btnNearest.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	btnNearest.Text         = "近い部位"
	btnNearest.Font         = Enum.Font.GothamBold
	btnNearest.TextSize     = 13
	btnNearest.TextColor3   = Color3.fromRGB(200, 200, 200)
	btnNearest.BorderSizePixel = 0
	btnNearest.Parent       = frame

	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0, 6)
	c1.Parent       = btnHead

	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 6)
	c2.Parent       = btnNearest

	local function refresh()
		if Settings.lockTarget == "Head" then
			btnHead.BackgroundColor3    = Color3.fromRGB(255, 80, 80)
			btnNearest.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			btnHead.TextColor3          = Color3.fromRGB(255, 255, 255)
			btnNearest.TextColor3       = Color3.fromRGB(160, 160, 160)
		else
			btnHead.BackgroundColor3    = Color3.fromRGB(40, 40, 50)
			btnNearest.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
			btnHead.TextColor3          = Color3.fromRGB(160, 160, 160)
			btnNearest.TextColor3       = Color3.fromRGB(255, 255, 255)
		end
	end

	btnHead.Activated:Connect(function()
		Settings.lockTarget = "Head"
		refresh()
	end)
	btnNearest.Activated:Connect(function()
		Settings.lockTarget = "Nearest"
		refresh()
	end)

	return frame
end

-- スライダー追加
makeSlider(SettingsPanel,
	"スタッド距離  (5〜30)", 5, 30, Settings.studsRange, 1,
	function(v)
		Settings.studsRange = v
	end)

makeSlider(SettingsPanel,
	"ロック円の半径  (60〜200px)", 60, 200, Settings.circleRadius, 2,
	function(v)
		Settings.circleRadius = v
		CircleFrame.Size = UDim2.new(0, v * 2, 0, v * 2)
		HoldFrame.Size   = UDim2.new(0, v * 2 + 12, 0, v * 2 + 12)
		LockLabel.Position = UDim2.new(0.5, 0, 0.5, v + 8)
	end)

makeSelector(SettingsPanel, 3)

-- 設定パネル開閉
SettingsBtn.Activated:Connect(function()
	settingsOpen = not settingsOpen
	SettingsPanel.Visible = settingsOpen
	SettingsBtn.BackgroundColor3 = settingsOpen
		and Color3.fromRGB(255, 80, 80)
		or  Color3.fromRGB(30, 30, 30)
end)

-- ============================================================
--  ▼ ロジック：スクリーン座標 → ロック円内判定
-- ============================================================
local function getScreenPos(worldPos)
	local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
	return Vector2.new(screenPos.X, screenPos.Y), onScreen, screenPos.Z
end

local function screenCenter()
	local vp = Camera.ViewportSize
	return Vector2.new(vp.X / 2, vp.Y / 2)
end

-- 対象キャラから候補パーツを列挙
local CANDIDATE_PARTS = {
	"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
	"RightUpperArm", "LeftUpperArm",
	"RightUpperLeg", "LeftUpperLeg",
}

local function getCandidatePart(character)
	if Settings.lockTarget == "Head" then
		return character:FindFirstChild("Head")
	end

	-- 近い部位モード：スクリーン中心に最も近いパーツを返す
	local center  = screenCenter()
	local bestPart = nil
	local bestDist = math.huge

	for _, name in ipairs(CANDIDATE_PARTS) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local sp, onScreen = getScreenPos(part.Position)
			if onScreen then
				local d = (sp - center).Magnitude
				if d < bestDist then
					bestDist = d
					bestPart = part
				end
			end
		end
	end

	return bestPart
end

-- キャラクターが有効か確認
local function isAlive(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

-- ============================================================
--  ▼ ロック対象を探す
--    条件：① スタッド内  ② ロック円内  ③ 生存
-- ============================================================
local function findLockTarget()
	local myChar = LocalPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end

	local center  = screenCenter()
	local best    = nil
	local bestScore = math.huge   -- 円中心からのスクリーン距離

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		local char = player.Character
		if not char or not isAlive(char) then continue end

		-- スタッド距離チェック
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end
		local dist3D = (root.Position - myRoot.Position).Magnitude
		if dist3D > Settings.studsRange then continue end

		-- 対象パーツ取得
		local part = getCandidatePart(char)
		if not part then continue end

		-- スクリーン座標チェック（円内）
		local sp, onScreen, depth = getScreenPos(part.Position)
		if not onScreen or depth < 0 then continue end

		local screenDist = (sp - center).Magnitude
		if screenDist > Settings.circleRadius then continue end

		if screenDist < bestScore then
			bestScore = screenDist
			best      = part
		end
	end

	return best
end

-- ============================================================
--  ▼ カメラロック（CFrame補正）
-- ============================================================
local function applyCameraLock(targetPart)
	if not targetPart or not targetPart.Parent then return end

	local targetPos = targetPart.Position
	local camCF     = Camera.CFrame
	local lookDir   = (targetPos - camCF.Position).Unit

	-- Y軸保持しながら水平回転
	local newCF = CFrame.new(camCF.Position, camCF.Position + lookDir)

	-- 急激な補正を避けるためAlpha補間
	Camera.CFrame = camCF:Lerp(newCF, 0.25)
end

-- ============================================================
--  ▼ タッチ入力：右側長押し検出
--     Roblox の右サムスティック = 画面右半分のタッチ
-- ============================================================
local holdTimer     = 0
local holdActive    = false
local rightTouchId  = nil   -- 右側タッチのID

-- ViewportSize の右半分をロックボタンとして扱う
local function isRightSide(pos)
	return pos.X > Camera.ViewportSize.X * 0.5
end

UserInputService.TouchStarted:Connect(function(inp, gpe)
	if gpe then return end
	if isRightSide(inp.Position) and not holdActive then
		holdActive   = true
		holdTimer    = 0
		rightTouchId = inp.UserInputState -- 実際はtouchIDはinpから
		HoldFrame.Visible = true
	end
end)

UserInputService.TouchEnded:Connect(function(inp, gpe)
	if isRightSide(inp.Position) then
		holdActive  = false
		holdTimer   = 0
		rightTouchId = nil
		HoldFrame.Visible = false

		if not locked then
			setCircleColor(Color3.fromRGB(255, 255, 255), 0.92)
		end
	end
end)

-- ============================================================
--  ▼ メインループ
-- ============================================================
RunService.RenderStepped:Connect(function(dt)
	local myChar = LocalPlayer.Character
	if not myChar then
		locked     = false
		lockedPart = nil
		return
	end

	-- ── 長押しタイマー更新 ──
	if holdActive then
		holdTimer = holdTimer + dt
		local progress = math.clamp(holdTimer / Settings.holdTime, 0, 1)

		-- ゲージ視覚（HoldFrame の透明度で表現）
		HoldFrame.BackgroundTransparency = 1
		HoldArc.Transparency = 1 - progress * 0.9

		if holdTimer >= Settings.holdTime and not locked then
			-- 長押し成立 → ロック試行
			local target = findLockTarget()
			if target then
				locked     = true
				lockedPart = target
				setCircleColor(Color3.fromRGB(255, 80, 80), 0.85)
				LockLabel.Text = "🔒 LOCKED"
			else
				setCircleColor(Color3.fromRGB(255, 255, 255), 0.92)
				LockLabel.Text = "対象なし"
				task.delay(0.8, function()
					if not locked then LockLabel.Text = "" end
				end)
			end
		end
	else
		-- 指を離した → ロック解除
		if locked then
			locked     = false
			lockedPart = nil
			setCircleColor(Color3.fromRGB(255, 255, 255), 0.92)
			LockLabel.Text = ""
		end
	end

	-- ── ロック中のカメラ追跡 ──
	if locked and lockedPart then
		-- ターゲットが死んだ / 消えた場合は解除
		if not lockedPart.Parent
		   or not isAlive(lockedPart.Parent) then
			locked     = false
			lockedPart = nil
			setCircleColor(Color3.fromRGB(255, 255, 255), 0.92)
			LockLabel.Text = ""
			return
		end

		-- スタッド距離再チェック
		local myRoot = myChar:FindFirstChild("HumanoidRootPart")
		if myRoot then
			local d = (lockedPart.Position - myRoot.Position).Magnitude
			if d > Settings.studsRange + 2 then   -- 少し余裕を持たせる
				locked     = false
				lockedPart = nil
				setCircleColor(Color3.fromRGB(255, 255, 255), 0.92)
				LockLabel.Text = "範囲外"
				task.delay(0.8, function() LockLabel.Text = "" end)
				return
			end
		end

		applyCameraLock(lockedPart)

		-- ロック中の円アニメーション（パルス）
		local pulse = math.sin(tick() * 6) * 0.05 + 0.85
		CircleFill.BackgroundTransparency = pulse
	end
end)
