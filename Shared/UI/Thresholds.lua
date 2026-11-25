-- Thresholds.lua: a proportional difficulty line with numeric boundaries and a current-value marker.
local ns = _G.NaowhForever

local Parts = ns.Shared.Parts
local St = ns.Shared.Style
local T = ns.THEME

local HALF = 0.5
local BANDS = 4
local TURN_UP = math.pi

local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function LabelY(line, row, usedRows)
    if line.above then return -(usedRows - row) * St.THRESHOLD_LABEL_HEIGHT end
    return -(line.barH + St.THRESHOLD_LABEL_GAP + (row - 1) * St.THRESHOLD_LABEL_HEIGHT)
end

local function PlaceBar(line, top)
    if not line.case or line.barTop == top then return end
    line.barTop = top
    local spec = line.spec
    line.case:ClearAllPoints()
    line.case:SetPoint("TOPLEFT", 0, -top)
    line.case:SetPoint("TOPRIGHT", 0, -top)
    line.track:ClearAllPoints()
    line.track:SetPoint("TOPLEFT", spec.padX, -(top + spec.padY))
    line.track:SetPoint("TOPRIGHT", -spec.padX, -(top + spec.padY))
end

local function Height(line, usedRows)
    if line.above then
        local top = usedRows * St.THRESHOLD_LABEL_HEIGHT + St.THRESHOLD_LABEL_GAP
        local below = line.skill and line.markerRoom or 0
        return top + line.barH + below, top
    end
    return St.THRESHOLD_HEIGHT - St.THRESHOLD_BAR_HEIGHT + line.barH
        + (usedRows - 1) * St.THRESHOLD_LABEL_HEIGHT, 0
end

local function Layout(line)
    local values = line.values
    if not values[4] then return end
    local inset = line.inset
    local width = math.max(1, line:GetWidth() - inset * 2)
    local span = (values[4] - values[1]) * (1 + St.THRESHOLD_GREY_SHARE)
    local usedRows = 1
    for i = 1, St.THRESHOLD_LABEL_ROWS do line.rowRights[i] = -St.THRESHOLD_LABEL_GAP end
    for i = 1, BANDS do
        local x = (values[i] - values[1]) / span * width
        local nextX = i < BANDS and (values[i + 1] - values[1]) / span * width or width
        local band = line.bands[i]
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", line.track, "TOPLEFT", x, 0)
        band:SetWidth(math.max(1, nextX - x))
        band:SetShown(nextX > x)
        local label = line.labels[i]
        label:SetShown(nextX > x)
        line.labelRows[i] = nil
        if nextX > x then
            local labelWidth = label:GetStringWidth()
            local left = Clamp(x - labelWidth * HALF, 0, math.max(0, width - labelWidth))
            local row = 1
            while row < St.THRESHOLD_LABEL_ROWS and left < line.rowRights[row] + St.THRESHOLD_LABEL_GAP do
                row = row + 1
            end
            label:SetShown(left >= line.rowRights[row] + St.THRESHOLD_LABEL_GAP)
            line.rowRights[row] = left + labelWidth
            usedRows = math.max(usedRows, row)
            line.labelRows[i], line.labelLefts[i] = row, left
        end
    end
    for i = 1, BANDS do
        local row = line.labelRows[i]
        if row then
            line.labels[i]:ClearAllPoints()
            line.labels[i]:SetPoint("TOPLEFT", line, "TOPLEFT", inset + line.labelLefts[i], LabelY(line, row, usedRows))
        end
    end
    local height, top = Height(line, usedRows)
    PlaceBar(line, top)
    line.markerLabel:SetShown(line.skill ~= nil and line.markerText ~= nil)
    if line.skill and line.markerText then
        local x = Clamp((line.skill - values[1]) / span, 0, 1) * width
        local labelWidth = line.markerLabel:GetStringWidth()
        local left = Clamp(x - labelWidth * HALF, 0, math.max(0, width - labelWidth))
        line.markerLabel:ClearAllPoints()
        line.markerLabel:SetPoint("TOPLEFT", line, "TOPLEFT", inset + left, -height)
        height = height + St.THRESHOLD_LABEL_HEIGHT
    end
    if line.drawnHeight ~= height then
        line.drawnHeight = height
        line:SetHeight(height)
    end
    line.marker:SetShown(line.skill ~= nil)
    if line.skill then
        local x = Clamp((line.skill - values[1]) / span, 0, 1) * width
        line.marker:ClearAllPoints()
        line.marker:SetPoint(line.markerAt, line.track, line.markerTo, x, 0)
    end
end

local function Fill(line, first, yellow, green, grey, skill, colors, markerText)
    line.values[1], line.values[2], line.values[3], line.values[4] = first, yellow, green, grey
    line.skill = skill
    line.markerText = markerText
    line.markerLabel:SetText(markerText or "")
    for i = 1, BANDS do
        line.labels[i]:SetText(tostring(line.values[i]))
        line.bands[i]:Paint(colors[i - 1])
    end
    Layout(line)
end

local function PaintBand(band, color)
    band:SetVertexColor(color.r, color.g, color.b, 1)
end

local function DrawnLine(line)
    ns.Border(line.track, St.BORDER_RGB)
    for i = 1, BANDS do
        local band = Parts.ProgressLine(line.track, St.THRESHOLD_BAR_HEIGHT)
        band:SetProgress(1)
        line.bands[i] = band
    end
    line.marker = CreateFrame("Frame", nil, line.track)
    line.marker:SetSize(St.THRESHOLD_MARKER_WIDTH, St.THRESHOLD_BAR_HEIGHT + St.THRESHOLD_MARKER_OUT * 2)
    line.marker:SetFrameLevel(line.bands[BANDS].fill:GetFrameLevel() + 1)
    ns.Solid(line.marker, "OVERLAY", T.fg, 1):SetAllPoints()
    line.markerAt, line.markerTo = "CENTER", "LEFT"
end

local function GameLine(line, spec)
    local case = CreateFrame("Frame", nil, line)
    case:SetPoint("TOPLEFT")
    case:SetPoint("TOPRIGHT")
    case:SetHeight(spec.h)
    if not Parts.ForeverSlicedRow(case, spec.track, spec.cap) then
        case:Hide()
        return false
    end
    line.case, line.spec, line.above = case, spec, true
    line.inset, line.barH = spec.padX, spec.h
    line.track:SetHeight(spec.h - spec.padY * 2)
    line.track:SetFrameLevel(case:GetFrameLevel() + 1)
    for i = 1, BANDS do
        local band = line.track:CreateTexture(nil, "ARTWORK")
        Parts.ForeverAtlas(band, spec.band)
        band:SetHeight(spec.h - spec.padY * 2)
        band.Paint = PaintBand
        line.bands[i] = band
    end
    line.marker = CreateFrame("Frame", nil, line.track)
    line.marker.arrow = line.marker:CreateTexture(nil, "OVERLAY")
    line.marker.arrow:SetAllPoints()
    local markerH = spec.markerH
    if Parts.ForeverAtlas(line.marker.arrow, spec.marker) then
        line.marker:SetSize(spec.markerW, markerH)
    else
        markerH = St.FOREVER_TIP_ARROW_H
        line.marker:SetSize(St.FOREVER_TIP_ARROW_W, markerH)
        line.marker.arrow:SetTexture(St.FOREVER_TIP_ARROW)
        local c = St.FOREVER_TIP_ARROW_COORDS
        line.marker.arrow:SetTexCoord(c[1], c[2], c[3], c[4])
        line.marker.arrow:SetRotation(TURN_UP)
    end
    line.markerAt, line.markerTo = "TOP", "BOTTOMLEFT"
    line.markerRoom = markerH - spec.padY
    return true
end

function Parts.ThresholdLine(parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(St.THRESHOLD_HEIGHT)
    line.values, line.bands, line.labels, line.rowRights = {}, {}, {}, {}
    line.labelRows, line.labelLefts = {}, {}
    line.inset, line.barH = 0, St.THRESHOLD_BAR_HEIGHT
    line.track = CreateFrame("Frame", nil, line)
    line.track:SetPoint("TOPLEFT")
    line.track:SetPoint("TOPRIGHT")
    line.track:SetHeight(St.THRESHOLD_BAR_HEIGHT)
    if not (ns.foreverSkin and GameLine(line, St.FOREVER_THRESHOLD)) then DrawnLine(line) end
    for i = 1, BANDS do
        local label = ns.Font(line, St.THRESHOLD_FONT_SIZE)
        label:SetJustifyH("LEFT")
        line.labels[i] = label
    end
    line.markerLabel = ns.Font(line, St.THRESHOLD_FONT_SIZE)
    line.markerLabel:SetJustifyH("LEFT")
    line.Fill = Fill
    line:SetScript("OnSizeChanged", Layout)
    return line
end
