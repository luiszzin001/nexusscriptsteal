--[[
   LocalScript – GUI moderna, interativa e animada
   Requisitos:
   - O usuário pode mover a janela pela tela.
   - O usuário pode minimizar e restaurar a janela com animações fluidas.
   - GUI limpa com cantos arredondados e botões de função.
   - Ao clicar em Configurações, escolher uma tecla de atalho (keybind).
   - Ao pressionar a keybind: gerar um bloco que se eleva gradualmente.
   - Ao clicar em Steal: Ativa a "capa lazer" e dispara continuamente.
]]

-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- State
local selectedKeyCode: Enum.KeyCode? = Enum.KeyCode.G -- default keybind
local isActive = false -- debounce for the elevator
local isPickingKey = false
local isStealActive = false
local stealLoop, childAddedConn, childRemovedConn
local isAimbotActive = false
local aimbotLoop, aimbotTargetRefreshLoop
local currentAimbotTarget: Instance? = nil
local AIMBOT_MAX_DISTANCE = 150 -- studs
local AIMBOT_REFRESH_INTERVAL = 0.2 -- seconds

-- Utility: get HRP
local function getRoot()
    local char = player.Character or player.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
    return char, hrp
end

-- Steal function logic (FIXED AND MORE ROBUST)
local function toggleSteal(button)
    isStealActive = not isStealActive
    
    if isStealActive then
        -- Wait for the "Laser Cape" tool to appear in the player's backpack or character
        local lazerTool = player.Backpack:WaitForChild("Laser Cape", 5) or (player.Character and player.Character:WaitForChild("Laser Cape", 5))
        
        if not lazerTool then
            print("Ferramenta 'Laser Cape' não encontrada na mochila ou no personagem.")
            isStealActive = false -- Revert activation if tool doesn't exist
            return
        end

        button.Text = "Steal ON"
        button.BackgroundColor3 = Color3.fromRGB(190, 40, 40)
        
        local char = player.Character
        if not char then isStealActive = false; return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then isStealActive = false; return end
        
        -- Ensure the tool is re-equipped if unequipped
        childRemovedConn = char.ChildRemoved:Connect(function(child)
            if child == lazerTool and isStealActive then
                task.wait() -- Wait one frame to avoid conflicts
                if humanoid and humanoid.Health > 0 then
                    humanoid:EquipTool(lazerTool)
                end
            end
        end)

        -- Awaits for the tool to be equipped before activating the fire loop
        local function startStealLoop()
            -- Clear previous loop if exists
            if stealLoop then stealLoop:Disconnect(); stealLoop = nil end

            -- Main loop to activate the tool
            stealLoop = RunService.Heartbeat:Connect(function()
                if lazerTool.Parent == char then
                    -- Ativar o tiro da ferramenta
                    lazerTool:Activate()
                    print("Ferramenta ativada.")
                end
            end)
        end

        -- If the tool is already equipped, start the loop immediately
        if lazerTool.Parent == char then
            startStealLoop()
        else
            -- If not, connect to an event to wait for the tool to be added
            childAddedConn = char.ChildAdded:Connect(function(child)
                if child == lazerTool then
                    childAddedConn:Disconnect()
                    startStealLoop()
                end
            end)
            -- Try to equip the tool, which will fire the ChildAdded event when it is done
            humanoid:EquipTool(lazerTool)
        end
    else
        -- Disconnect loops and events to stop functionality
        if stealLoop then stealLoop:Disconnect(); stealLoop = nil end
        if childRemovedConn then childRemovedConn:Disconnect(); childRemovedConn = nil end
        if childAddedConn then childAddedConn:Disconnect(); childAddedConn = nil end
        
        button.Text = "Steal"
        button.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
    end
end

-- Aimbot helpers and toggle
local function isHumanoidAlive(humanoid: Humanoid?)
    return humanoid and humanoid.Health and humanoid.Health > 0
end

local function validateTarget(model: Model?)
    if not model or not model.Parent then return false end
    local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid")
    local hrp: BasePart? = model:FindFirstChild("HumanoidRootPart")
    return isHumanoidAlive(humanoid) and hrp ~= nil
end

local function getNearestTarget(maxDistance: number)
    local localChar = player.Character
    if not localChar then return nil end
    local localHRP: BasePart? = localChar:FindFirstChild("HumanoidRootPart")
    if not localHRP then return nil end

    local nearest: Model? = nil
    local nearestDist = math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
            local char: Model? = plr.Character
            if validateTarget(char) then
                local hrp: BasePart = char:FindFirstChild("HumanoidRootPart")
                local dist = (hrp.Position - localHRP.Position).Magnitude
                if dist < nearestDist and dist <= maxDistance then
                    nearest = char
                    nearestDist = dist
                end
            end
        end
    end
    return nearest
end

-- Try to orient the equipped tool (Laser Cape) toward the target without moving camera/character
local function getEquippedLaserTool()
    local char = player.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool.Name == "Laser Cape" then
            return tool
        end
    end
    return nil
end

local function aimToolAt(targetModel: Model)
    local tool = getEquippedLaserTool()
    if not tool then return end
    local head: BasePart? = targetModel:FindFirstChild("Head") or targetModel:FindFirstChild("HumanoidRootPart")
    if not head then return end

    -- Prefer a handle part; otherwise, try first BasePart descendant
    local handle: BasePart? = tool:FindFirstChild("Handle") :: BasePart
    if not handle then
        for _, d in ipairs(tool:GetDescendants()) do
            if d:IsA("BasePart") then
                handle = d
                break
            end
        end
    end
    if not handle then return end

    -- Smoothly orient the handle to look at the target's head/HRP
    local fromPos = handle.Position
    local desired = CFrame.lookAt(fromPos, head.Position)
    -- Blend to reduce jitter
    local alpha = 0.4
    handle.CFrame = handle.CFrame:Lerp(desired, alpha)
end

local function toggleAimbot(button: TextButton)
    isAimbotActive = not isAimbotActive

    if isAimbotActive then
        button.Text = "Aimbot ON"
        button.BackgroundColor3 = Color3.fromRGB(60, 120, 220)

        -- Periodically refresh target
        if aimbotTargetRefreshLoop then aimbotTargetRefreshLoop:Disconnect(); aimbotTargetRefreshLoop = nil end
        aimbotTargetRefreshLoop = RunService.Heartbeat:Connect(function()
            -- Use timer to throttle
            local last = (button :: any)._lastRefresh or 0
            local now = time()
            if now - last >= AIMBOT_REFRESH_INTERVAL then
                (button :: any)._lastRefresh = now
                local tgt = getNearestTarget(AIMBOT_MAX_DISTANCE)
                if tgt and validateTarget(tgt) then
                    currentAimbotTarget = tgt
                else
                    currentAimbotTarget = nil
                end
            end
        end)

        -- Aim every render step if target valid (orient tool only; do not move camera)
        if aimbotLoop then aimbotLoop:Disconnect(); aimbotLoop = nil end
        aimbotLoop = RunService.RenderStepped:Connect(function()
            if currentAimbotTarget and validateTarget(currentAimbotTarget :: Model) then
                aimToolAt(currentAimbotTarget :: Model)
            end
        end)
    else
        if aimbotLoop then aimbotLoop:Disconnect(); aimbotLoop = nil end
        if aimbotTargetRefreshLoop then aimbotTargetRefreshLoop:Disconnect(); aimbotTargetRefreshLoop = nil end
        currentAimbotTarget = nil

        button.Text = "Aimbot"
        button.BackgroundColor3 = Color3.fromRGB(30, 80, 160)
    end
end

-- Modern and interactive GUI
local function createGui()
    -- Ensure there are no duplicate GUIs
    local oldGui = player:WaitForChild("PlayerGui"):FindFirstChild("ElevatorBlockGUI")
    if oldGui then oldGui:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ElevatorBlockGUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = player:WaitForChild("PlayerGui")

    -- Main container
    local frame = Instance.new("Frame")
    frame.Name = "MainPanel"
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    -- (REMOVED) The line that defined the initial size as 0 in height was removed.
    -- AutomaticSize along with UISizeConstraint will take care of this.
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    frame.BackgroundTransparency = 0.15 -- Glass effect
    frame.ClipsDescendants = true -- Essential for the minimize animation
    frame.Parent = screenGui

    -- Layout and Style
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = frame

    local vLayout = Instance.new("UIListLayout")
    vLayout.Padding = UDim.new(0, 8)
    vLayout.SortOrder = Enum.SortOrder.LayoutOrder
    vLayout.Parent = frame

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(280, 42)
    sizeConstraint.MaxSize = Vector2.new(420, 300)
    sizeConstraint.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = Color3.fromRGB(255, 140, 0)
    stroke.Transparency = 0.5
    stroke.Parent = frame

    -- Header (Drag area)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
    header.BackgroundTransparency = 0.2
    header.Size = UDim2.new(1, 0, 0, 32)
    header.LayoutOrder = 1 -- Ensure the header comes first
    header.Parent = frame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 8)
    headerCorner.Parent = header

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -40, 1, 0) -- Space for the minimize button
    title.Position = UDim2.fromOffset(0, 0)
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.TextColor3 = Color3.fromRGB(255, 105, 180)
    title.Text = "Nexus System"
    title.Parent = header

    -- Minimize/Maximize button
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "MinimizeButton"
    minimizeBtn.AnchorPoint = Vector2.new(1, 0.5)
    minimizeBtn.Position = UDim2.new(1, -5, 0.5, 0)
    minimizeBtn.Size = UDim2.new(0, 22, 0, 22)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.BackgroundTransparency = 0.9
    minimizeBtn.Text = "–" -- Minimize symbol
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.TextSize = 20
    minimizeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    minimizeBtn.Parent = header
    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0, 6)
    minCorner.Parent = minimizeBtn

    -- Content that will be hidden
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.LayoutOrder = 2
    content.Parent = frame
    local contentLayout = Instance.new("UIListLayout")
    contentLayout.Padding = UDim.new(0, 8)
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Parent = content

    -- Detect platform capability
    local isMobile = UserInputService.TouchEnabled == true

    -- Keybind label (hidden on mobile)
    local keyLabel = Instance.new("TextLabel")
    keyLabel.Name = "KeyLabel"
    keyLabel.BackgroundTransparency = 1
    keyLabel.Size = UDim2.new(1, 0, 0, 18)
    keyLabel.Font = Enum.Font.Gotham
    keyLabel.TextSize = 14
    keyLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
    keyLabel.Text = "Tecla: " .. (selectedKeyCode and selectedKeyCode.Name or "Nenhuma")
    keyLabel.Visible = not isMobile
    keyLabel.Parent = content

    -- Bottom bar with buttons
    local bottomBar = Instance.new("Frame")
    bottomBar.Name = "BottomBar"
    bottomBar.BackgroundTransparency = 1
    bottomBar.Size = UDim2.new(1, 0, 0, 32)
    bottomBar.Parent = content

    local hLayout = Instance.new("UIListLayout")
    hLayout.FillDirection = Enum.FillDirection.Horizontal
    hLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    hLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    hLayout.Padding = UDim.new(0, 8)
    hLayout.Parent = bottomBar

    -- Steal button
    local stealBtn = Instance.new("TextButton")
    stealBtn.Name = "StealButton"
    stealBtn.Size = UDim2.new(0.45, 0, 1, 0)
    stealBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
    stealBtn.Text = "Steal"
    stealBtn.Font = Enum.Font.GothamSemibold
    stealBtn.TextSize = 14
    stealBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    stealBtn.Parent = bottomBar
    local stealCorner = Instance.new("UICorner")
    stealCorner.CornerRadius = UDim.new(0, 8)
    stealCorner.Parent = stealBtn
    local stealGradient = Instance.new("UIGradient")
    stealGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 200, 120)),ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 160, 90))})
    stealGradient.Rotation = 90
    stealGradient.Parent = stealBtn

    -- Config button (hidden on mobile)
    local configBtn = Instance.new("TextButton")
    configBtn.Name = "ConfigButton"
    configBtn.Size = UDim2.new(0.45, 0, 1, 0)
    configBtn.BackgroundColor3 = Color3.fromRGB(190, 40, 40)
    configBtn.Text = "Config"
    configBtn.Font = Enum.Font.GothamSemibold
    configBtn.TextSize = 14
    configBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    configBtn.Visible = not isMobile
    configBtn.Parent = bottomBar
    local configCorner = Instance.new("UICorner")
    configCorner.CornerRadius = UDim.new(0, 8)
    configCorner.Parent = configBtn
    local configGradient = Instance.new("UIGradient")
    configGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 95, 95)), ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 30, 30))})
    configGradient.Rotation = 90
    configGradient.Parent = configBtn

    -- If mobile, widen the Steal button since Config is hidden
    if isMobile then
        stealBtn.Size = UDim2.new(0.93, 0, 1, 0)
    end

    -- Second row with Aimbot button (placed below Steal/Config)
    local bottomBar2 = Instance.new("Frame")
    bottomBar2.Name = "BottomBar2"
    bottomBar2.BackgroundTransparency = 1
    bottomBar2.Size = UDim2.new(1, 0, 0, 32)
    bottomBar2.Parent = content

    local hLayout2 = Instance.new("UIListLayout")
    hLayout2.FillDirection = Enum.FillDirection.Horizontal
    hLayout2.HorizontalAlignment = Enum.HorizontalAlignment.Center
    hLayout2.VerticalAlignment = Enum.VerticalAlignment.Center
    hLayout2.Padding = UDim.new(0, 8)
    hLayout2.Parent = bottomBar2

    local aimbotBtn = Instance.new("TextButton")
    aimbotBtn.Name = "AimbotButton"
    aimbotBtn.Size = isMobile and UDim2.new(0.45, 0, 1, 0) or UDim2.new(0.93, 0, 1, 0)
    aimbotBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 160)
    aimbotBtn.Text = "Aimbot"
    aimbotBtn.Font = Enum.Font.GothamSemibold
    aimbotBtn.TextSize = 14
    aimbotBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    aimbotBtn.Parent = bottomBar2
    local aimbotCorner = Instance.new("UICorner")
    aimbotCorner.CornerRadius = UDim.new(0, 8)
    aimbotCorner.Parent = aimbotBtn
    local aimbotGradient = Instance.new("UIGradient")
    aimbotGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 140, 240)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 80, 160))
    })
    aimbotGradient.Rotation = 90
    aimbotGradient.Parent = aimbotBtn

    -- Elevator button for mobile click-to-spawn platform
    local elevatorBtn, elevatorCorner, elevatorGradient
    if isMobile then
        elevatorBtn = Instance.new("TextButton")
        elevatorBtn.Name = "ElevatorButton"
        elevatorBtn.Size = UDim2.new(0.45, 0, 1, 0)
        elevatorBtn.BackgroundColor3 = Color3.fromRGB(90, 160, 230)
        elevatorBtn.Text = "Elevator"
        elevatorBtn.Font = Enum.Font.GothamSemibold
        elevatorBtn.TextSize = 14
        elevatorBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        elevatorBtn.Parent = bottomBar2
        elevatorCorner = Instance.new("UICorner")
        elevatorCorner.CornerRadius = UDim.new(0, 8)
        elevatorCorner.Parent = elevatorBtn
        elevatorGradient = Instance.new("UIGradient")
        elevatorGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 190, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 160, 230))
        })
        elevatorGradient.Rotation = 90
        elevatorGradient.Parent = elevatorBtn
    end

    -- Key selection popup
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Visible = false
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.35
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.ZIndex = 10
    overlay.Parent = screenGui

    local picker = Instance.new("Frame")
    picker.Name = "KeyPicker"
    picker.AnchorPoint = Vector2.new(0.5, 0.5)
    picker.Position = UDim2.new(0.5, 0, 0.5, 0)
    picker.Size = UDim2.new(0, 320, 0, 140)
    picker.BackgroundColor3 = Color3.fromRGB(26, 28, 34)
    picker.Parent = overlay
    local pickerCorner = Instance.new("UICorner")
    pickerCorner.CornerRadius = UDim.new(0, 12)
    pickerCorner.Parent = picker

    local pickerInfo = Instance.new("TextLabel")
    pickerInfo.BackgroundTransparency = 1
    pickerInfo.Size = UDim2.new(1, -20, 0, 40)
    pickerInfo.Position = UDim2.new(0, 10, 0, 46)
    pickerInfo.Font = Enum.Font.Gotham
    pickerInfo.TextSize = 14
    pickerInfo.TextWrapped = true
    pickerInfo.TextXAlignment = Enum.TextXAlignment.Center
    pickerInfo.TextColor3 = Color3.fromRGB(180, 190, 205)
    pickerInfo.Text = "Pressione qualquer tecla...\n(Esc para cancelar)"
    pickerInfo.Parent = picker

    -- --- GUI INTERACTION LOGIC ---

    -- 1. Drag the window
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    header.InputChanged:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- 2. Minimize/Maximize Animation
    local isMinimized = false
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        content.Visible = not isMinimized
        minimizeBtn.Text = isMinimized and "□" or "–"
        
        -- To ensure a smooth animation, we temporarily disable AutomaticSize
        frame.AutomaticSize = Enum.AutomaticSize.None
        
        local currentSize = frame.AbsoluteSize
        local targetSizeY = isMinimized and header.AbsoluteSize.Y or (header.AbsoluteSize.Y + content.AbsoluteSize.Y + vLayout.Padding.Offset + (padding.PaddingTop.Offset * 2))

        local tween = TweenService:Create(frame, tweenInfo, {Size = UDim2.fromOffset(currentSize.X, targetSizeY)})
        tween:Play()

        tween.Completed:Connect(function()
            if not isMinimized then
                -- Re-enable AutomaticSize after the maximize animation
                frame.AutomaticSize = Enum.AutomaticSize.Y
            end
        end)
    end)

    -- 3. Hover effects on buttons
    local function createHoverEffect(button, grad, c1, c2, c3, c4)
        button.MouseEnter:Connect(function() grad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2)}) end)
        button.MouseLeave:Connect(function() grad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, c3), ColorSequenceKeypoint.new(1, c4)}) end)
    end
    createHoverEffect(stealBtn, stealGradient, Color3.fromRGB(90, 220, 140), Color3.fromRGB(50, 180, 100), Color3.fromRGB(80, 200, 120), Color3.fromRGB(40, 160, 90))
    if not isMobile then
        createHoverEffect(configBtn, configGradient, Color3.fromRGB(255, 115, 115), Color3.fromRGB(190, 50, 50), Color3.fromRGB(255, 95, 95), Color3.fromRGB(170, 30, 30))
    end
    createHoverEffect(aimbotBtn, aimbotGradient, Color3.fromRGB(90, 170, 255), Color3.fromRGB(50, 120, 210), Color3.fromRGB(70, 140, 240), Color3.fromRGB(30, 80, 160))
    if isMobile and elevatorBtn and elevatorGradient then
        createHoverEffect(elevatorBtn, elevatorGradient, Color3.fromRGB(150, 210, 255), Color3.fromRGB(110, 180, 245), Color3.fromRGB(120, 190, 255), Color3.fromRGB(90, 160, 230))
    end

    -- 4. Key selection logic
    local keybindConnection
    local function openPicker()
        if isPickingKey then return end
        isPickingKey = true
        overlay.Visible = true

        -- Connect the input event only when the picker is open
        keybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if not isPickingKey then return end
            
            if input.UserInputType == Enum.UserInputType.Keyboard then
                isPickingKey = false
                overlay.Visible = false
                
                if input.KeyCode ~= Enum.KeyCode.Escape then
                    selectedKeyCode = input.KeyCode
                    keyLabel.Text = "Tecla: " .. selectedKeyCode.Name
                end
                
                if keybindConnection then
                    keybindConnection:Disconnect()
                    keybindConnection = nil
                end
            end
        end)
    end

    if not isMobile then
        configBtn.MouseButton1Click:Connect(openPicker)
    end

    -- Steal button interaction
    stealBtn.MouseButton1Click:Connect(function()
        toggleSteal(stealBtn)
    end)

    -- Aimbot button interaction
    aimbotBtn.MouseButton1Click:Connect(function()
        toggleAimbot(aimbotBtn)
    end)

    -- Elevator button interaction (mobile only)
    if isMobile and elevatorBtn then
        elevatorBtn.MouseButton1Click:Connect(function()
            -- Use existing flow with debounce inside spawnElevatorBlock
            spawnElevatorBlock(1.2, 15)
        end)
    end

    -- Cleanup if GUI is destroyed
    screenGui.Destroying:Connect(function()
        if isStealActive then
            toggleSteal(stealBtn)
        end
        if isAimbotActive then
            toggleAimbot(aimbotBtn)
        end
    end)
end

-- Elevator block logic (unchanged)
local function spawnElevatorBlock(durationSeconds: number, liftHeight: number)
    if isActive then return end
    isActive = true
    local char, hrp = getRoot()
    if not hrp then isActive = false; return end
    local startPos = hrp.Position - Vector3.new(0, (hrp.Size.Y/2) + 2, 0)
    local part = Instance.new("Part")
    part.Name = "ElevatorBlock"
    part.Size = Vector3.new(6, 1, 6)
    part.Color = Color3.fromRGB(80, 160, 255)
    part.Material = Enum.Material.Neon
    part.Anchored = true
    part.CanCollide = true
    part.CFrame = CFrame.new(startPos.X, startPos.Y, startPos.Z)
    part.Parent = workspace
    local sel = Instance.new("SelectionBox")
    sel.LineThickness = 0.03
    sel.Color3 = Color3.fromRGB(180, 220, 255)
    sel.Adornee = part
    sel.Parent = part
    local startTime = time()
    local startY = part.Position.Y
    local targetY = startY + liftHeight
    local steppedConn
    steppedConn = RunService.RenderStepped:Connect(function()
        if not part or not part.Parent then steppedConn:Disconnect(); return end
        local _, currentHrp = getRoot()
        if not currentHrp then part:Destroy(); steppedConn:Disconnect(); return end
        local hrpPos = currentHrp.Position
        local elapsed = math.clamp((time() - startTime) / durationSeconds, 0, 1)
        local currentY = startY + (targetY - startY) * elapsed
        part.CFrame = CFrame.new(hrpPos.X, currentY, hrpPos.Z)
        if elapsed >= 1 then
            steppedConn:Disconnect()
            task.delay(0.05, function() if part and part.Parent then part:Destroy() end end)
            isActive = false
        end
    end)
end

-- Listen for keypress (unchanged)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if UserInputService.TouchEnabled then return end -- desktop-only keybind
    if gameProcessed or isPickingKey then return end
    if input.UserInputType == Enum.UserInputType.Keyboard and selectedKeyCode and input.KeyCode == selectedKeyCode then
        spawnElevatorBlock(1.2, 15)
    end
end)

-- Extra security (unchanged)
player.CharacterAdded:Connect(function(char)
    isActive = false
    if isStealActive then
        local gui = player.PlayerGui:FindFirstChild("ElevatorBlockGUI")
        if gui then
            local stealBtn = gui.MainPanel.Content.BottomBar.StealButton
            toggleSteal(stealBtn) -- Call the function to reset the state
        end
    end
    if isAimbotActive then
        local gui = player.PlayerGui:FindFirstChild("ElevatorBlockGUI")
        if gui then
            local aimbotBtn = gui.MainPanel.Content.BottomBar2.AimbotButton
            toggleAimbot(aimbotBtn)
        end
    end
end)

-- Start the GUI
createGui()
