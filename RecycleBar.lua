---@class RecycleBar : SXLuaMonoBehaviourAPI
---@author
---
---@field public rt UnityEngine.RectTransform
---@field public area ScrollRectExtension
---@field public rectTransform UnityEngine.RectTransform
---
---@field public owner
---@field public maxCount number
---@field public poolCount number 对象池数量
---@field public children table
---@field public spaceX number
---@field public gridWidth number
---@field private datas
---@field private startPos
---@field private endPos
---@field private centerIndex number 定位组间中心位置
---
---@field public onPosChange function 当位置变化时
---
local RecycleBar = class("RecycleBar")

function RecycleBar:OnInit(hasCenter)
    self.hasCenter = hasCenter
    self.Moving = false
end

---@public
---初始化
function RecycleBar:SetConfig(owner, count, space, gridWidth, offsetHeight, creator, onPosChange)
    self.owner = owner
    self.maxCount = count
    self.spaceX = space
    self.gridWidth = gridWidth
    self.offsetHeight = offsetHeight
    self.creator = creator
    self.onPosChange = onPosChange
    self.onStop = nil
    
    self.curIndex = 1
    self.minSpeed = 50
    self.lastPosX = self.rt.localPosition.x
    self.width = self.rectTransform.rect.width
    
    -- left, up, right, down
    self.board = Vector4(0,0,0,0)
    
    self.children = {}
    self:addEvent()
    
    -- 确保功能正常
    self.isReady = true
end

---@public
---设置移动音效
function RecycleBar:SetAudio(id)
    self.audioID = id
    self.playAudio = true
end

---@public
---设置左右 board 
function RecycleBar:SetBoard(board)
    self.board = board
end

---@public
---设置数据
function RecycleBar:SetDatas(datas)
    if not self.isReady then
        if AppMode.IsDevelopment then 
            SXLog.LogError("RecycleBar not initial")
        end
        return 
    end
    
    -- clear children
    self.area:StopMovement()
    
    local num = #self.children
    if num > #datas then
        for i = 1, (num - #datas) do
            GameObject.Destroy(self.children[1].gameObject)
            table.remove(self.children, 1)
        end
    end

    num = #self.children 
    
    self.datas = datas
    -- 超出边界部分重新计算
    self.maxWidth = self.maxCount * (self.gridWidth + self.spaceX)
    self.offset = (self.width - self.maxWidth) / 2
    if self.offset < 0 then 
        self.offset = 0
    end
    
    local min = math.min(self.maxCount, #datas)
    local max = math.max(self.maxCount, #datas) 
    if self.hasCenter then
        self.centerIndex = math.ceil(min / 2)
    else
        self.centerIndex = 1
    end
    
    -- 边界范围
    self.limit = {
        min = -self.gridWidth / 3 + self.offset,
        max = (self.width + self.gridWidth / 3) - self.offset
    }
    
    -- 可滚动尺寸
    local rx = max * (self.gridWidth + self.spaceX) + self.offset * 2
    rx = rx + self.board.x + self.board.z
    local ry = self.rt.sizeDelta.y
    ry = ry + self.board.y + self.board.w
    self.rt.sizeDelta = Vector2(rx, ry)

    if num < min then
        for i = 1, (min - num) do
            local item = self.creator(self.rt)
            table.insert(self.children, item)
            item.curIndex = i
            item.gameObject.name = i
            item:updateData(self.datas[item.curIndex])
            local tx = self:GetAnchorX(i - 1)
            item.rectTransform.localPosition = Vector3(tx, self.offsetHeight, 0)
            tx = tx + self.rt.localPosition.x

            if self.onPosChange then
                self.onPosChange(self, item)
            end
        end
    else
        self:Recaculate()
    end

    if self.hasCenter then
        self:alignCenter(nil,true)
    else
        -- amberResearch
        self:RefreshAll(true)
    end
end

function RecycleBar:Recaculate()
    -- update data only
    for _, v in pairs(self.children) do
        v.curIndex = _
        v.gameObject.name = v.curIndex
        v:updateData(self.datas[_])
        local tx = self:GetAnchorX(_ - 1)
        v.rectTransform.localPosition = Vector3(tx, self.offsetHeight, 0)
        tx = tx + self.rt.localPosition.x
    end
end

---@public
---记录 area 位置
function RecycleBar:RecordLastPos()
    self.lastPosX = self.rt.localPosition.x
end

---@public
function RecycleBar:MoveToPosX()
    self.rt:DOLocalMoveX(self.lastPosX, 0.2):OnUpdate(function()
        self:RefreshAll()
    end)
end

---@private
---增加事件
function RecycleBar:addEvent()
    self.area.onValueChanged:AddListener(HandlerBind(self, self.RefreshAll))
    self.area.onBeginDrag = HandlerBind(self, self.onBeginDrag)
    self.area.onEndDrag = HandlerBind(self, self.onEndDrag)
end

---@public
---刷新数据
function RecycleBar:RefreshAll(isForce)
    -- SXLog.LogError("[AdventurePanel] move on value change")
    local dx = self.rt.localPosition.x
    if math.abs(self.lastPosX - dx) < 15 and not isForce then 
        return
    end
    
    local nIndex = 0
    local x = 0
    
    self.isDirty = false
    self.lastPosX = dx
    for _, v in pairs(self.children) do
        -- move item to next position
        local tx = (v.rectTransform.localPosition.x + dx)
        if tx < self.limit.min and (v.curIndex + #self.children <= #self.datas) then
            nIndex = v.curIndex + #self.children
            x = self:GetAnchorX( nIndex - 1)
            while (x + dx) < -self.gridWidth / 2 do 
                nIndex = nIndex + #self.children
                x = self:GetAnchorX( nIndex - 1)
            end
            v.curIndex = nIndex
            v.gameObject.name = v.curIndex
            v:updateData(self.datas[v.curIndex])
            v.gameObject:SetLocalPosition(x, self.offsetHeight, 0)
            self.isDirty = true
            
            if self.playAudio then 
                AudioManager:PlayAudio(self.audioID)
            end
            
        end
        
        if tx >= self.limit.max and (v.curIndex - #self.children > 0) then
            nIndex = v.curIndex - #self.children
            x = self:GetAnchorX( nIndex - 1)
            while (x + dx) > self.limit.max do
                nIndex = nIndex - #self.children
                x = self:GetAnchorX( nIndex - 1)
            end
            
            v.curIndex =  nIndex
            v.gameObject.name = v.curIndex
            v:updateData(self.datas[v.curIndex])
            v.gameObject:SetLocalPosition(x, self.offsetHeight, 0)
            self.isDirty = true
            
            if self.playAudio then
                AudioManager:PlayAudio(self.audioID)
            end
        end

        if self.onPosChange then
            self.onPosChange(self, v)
        end 
    end

    if self.hasCenter then
        self:tryStopMovementToCenter()
    end
end

---@private
---移动式尝试判断是否需要停止
function RecycleBar:tryStopMovementToCenter()
    if self.isDrag then 
        return
    end

    local dx = self.rt.localPosition.x
    -- velocity
    local sx = self.area.velocity.x
    local absSx = math.abs(sx)
    if sx == 0 then
        return
    end
    
    if self.isDirty then 
        self.center = self:GetSortChild(self.centerIndex)
    end
    
    -- offset 
    local tx = self.width / 2 - (self.center.rectTransform.localPosition.x + dx)
    local absTx = math.abs(tx)
    
    if (absSx < self.minSpeed and absSx > absTx)then 
        self:stopAlign()
        return
    end
    
    -- 当速度 小于指定范围并且不足以到达中心点时，给予额外的速度
    if absSx < (self.gridWidth / 2) and absSx < absTx then
        if tx > self.minSpeed and sx < -self.minSpeed then
            self.center = self:GetSortChild(self.centerIndex + 1)
            tx = self.width / 2 - (self.center.rectTransform.localPosition.x + dx)
        elseif tx < -self.minSpeed and sx > self.minSpeed then
            self.center = self:GetSortChild(self.centerIndex - 1)
            tx = self.width / 2 - (self.center.rectTransform.localPosition.x + dx)
        end

        SXLog.LogError("--------------Center:"..self.centerIndex)
        SXLog.LogError("--------------:"..tx)
        self.area.velocity = Vector3(tx, 0, 0)
    end
end

---@private
---尝试停止靠近最近中心
function RecycleBar:tryStopMovement()
    if self.Moving or self.isDrag then 
        return
    end

    -- distance middle 
    local d = 0
    local dm = 99999
    for _, v in pairs(self.children) do
        d = self.width / 2 - (v.rectTransform.localPosition.x + self.rt.localPosition.x)
        if math.abs(d) < dm then
            dm = math.abs(d)
            self.curIndex = v.curIndex
        end
    end
    
    if math.abs(self.area.velocity.x) > self.minSpeed and dm > (self.gridWidth / 3 * 2) then
        if self.area.velocity.x < 0 then
            self.curIndex = self.curIndex + 1
        else
            self.curIndex = self.curIndex - 1
        end
    end
    
    self.curIndex = math.min(#self.datas, math.max(1, self.curIndex))
    self.area.velocity = Vector3(0, 0, 0)
    local vec = 0
    for _, v in pairs(self.children) do 
        if v.curIndex == self.curIndex then
            vec = self.width / 2 - (v.rectTransform.localPosition.x) 
        end
    end
    
    self.Moving = true
    self.rt.transform:DOLocalMoveX(vec, 0.2):OnUpdate(function()
        self:RefreshAll()
    end)
end

---@private
---停止对齐动作
function RecycleBar:onBeginDrag(pos)
    self.isDrag = true
    self.Moving = false
    self.startPos = pos
    self.area:StopMovement()
end

function RecycleBar:onEndDrag(pos)
    self.isDrag = false
    if math.abs(self.area.velocity.x) < self.minSpeed then
        self:alignCenter()
    else
        if not self.hasCenter then
            self:tryStopMovement()
        end
    end 
end

function RecycleBar:stopAlign()
    if self.tween then
        self.tween:Kill()
        self.tween = nil
    end
    self.area:StopMovement()
end

---@private
---自动对齐 hasCenter only
function RecycleBar:alignCenter(pos, isImmediate)
    local d = {}
    for _,v in pairs(self.children) do
        table.insert(d, v.curIndex)
    end

    self.center = self:GetSortChild(self.centerIndex)
    
    local dt = 0.5
    if isImmediate then 
        dt = 0
    end
    
    local dx = self.width / 2 - self.center.rectTransform.localPosition.x
    self.tween = self.rt.transform:DOLocalMoveX(dx, dt)
end

---@public
---获取子节点
function RecycleBar:GetChild(index)
    return self.children[index]
end

---@public
---定位位置
---@param index number
---@param isMove boolean
---@return number
function RecycleBar:LocatePos(index, isMove, callBack)
    if index > #self.datas then
        return self.gridWidth / 2    -- default pos
    end
    
    local t = 0
    local mt = 0
    local limit = (#self.datas - #self.children + 1)
    if index > 2 then
        if index > limit then
            t = limit - 1
            mt = index - limit - 1
        else
            t = index - 2
        end
    end
    
    local d = (self.spaceX + self.gridWidth) * t
    local dt = (d / self.width) / 8
    if not isMove or dt < 0.3 then
        dt = 0.3
    end
    
    -- 放置任务定位的时候，velocity != 0 的情况，会导致偏移
    self.isDrag = true
    self.rt.transform:DOLocalMoveX(-d, dt):OnUpdate(function()
        self:RefreshAll()
    end):OnComplete(HandlerBindParams(self, self.onLocalComplete, mt, callBack))
end

function RecycleBar:onLocalComplete(mt, callBack)
    -- 额外刷新一次，避免出现 size 错误
    -- SXSchedule:AddScheduleTimer(self.RefreshAll, self, 0, 0.5, 1)
    local uiCamera = FAGamePlay.MapObjectMgr.SceneMove.uiCamera
    -- 特殊计算
    local posX = (uiCamera:WorldToViewportPoint(self:GetSortChild(mt + 2).transform.position).x - 0.5) * self.width
    self.owner:switchArrowObj(Vector2(posX, 200))
    self.isDrag = false
    self.area:StopMovement()
    if callBack then
        callBack()
    end
end

---@public
---定位功能
---@param pos 
function RecycleBar:LocateIndex(pos)
    
end

function RecycleBar:GetSortChild(index)
    local d = {}
    for _,v in pairs(self.children) do
        table.insert(d, v.curIndex)
    end
    table.sort(d)
    
    -- 超出范围
    if index > #self.children or index <= 0 then 
        index = 1
    end
    
    local target = table.find(self.children, function(v)
        return v.curIndex == d[index]
    end)
    
    return target
end

---@public
---@return Vector3
function RecycleBar:GetCenterPos()
    local target = self:GetSortChild(self.centerIndex)
    return target.rectTransform.localPosition
end

---@public
---locat is center
function RecycleBar:GetAnchorX(index)
    return (self.gridWidth / 2 + ((self.gridWidth + self.spaceX) * index - 1)) + self.offset + self.board.x
end

---@public
---remove all items
function RecycleBar:Reset()
    self.rt:DestroyChildren()
end
---去除事件

---@public
function RecycleBar:RemoveEvent()
    SXEventManager:RemoveAllEvent(self)
end

return RecycleBar