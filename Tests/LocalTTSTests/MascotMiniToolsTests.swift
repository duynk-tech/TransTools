import XCTest
@testable import TransTools

final class MascotMiniToolsTests: XCTestCase {
    @MainActor func testSwitchingToolsRetainsIndependentDrafts() {
        let state = MascotMiniToolsState()
        state.translation.text = "Review PR giúp mình"
        state.readerText = "Đoạn văn cần nghe"
        state.readerLanguage = .english
        state.conversationInput = "Câu chưa gửi"
        for tool in MascotMiniTool.allCases { state.tool = tool }
        XCTAssertEqual(state.translation.text, "Review PR giúp mình")
        XCTAssertEqual(state.readerText, "Đoạn văn cần nghe")
        XCTAssertEqual(state.readerLanguage, .english)
        XCTAssertEqual(state.conversationInput, "Câu chưa gửi")
        state.translation.cancel()
        XCTAssertEqual(state.translation.text, "Review PR giúp mình")
    }
    func testMiniRoutesMatchFullDashboardTabs() {
        XCTAssertEqual(MascotMiniTool.translation.rawValue, 2)
        XCTAssertEqual(MascotMiniTool.reader.rawValue, 6)
        XCTAssertEqual(MascotMiniTool.conversation.rawValue, 5)
        XCTAssertNil(MascotMiniTool(rawValue: 0))
    }
    func testMascotOrbitOutsideClickRegionIncludesIconsAndTooltipButExcludesTransparentCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 360)
        XCTAssertTrue(MascotOutsideClickPolicy.contains(CGPoint(x: 180, y: 180), in: bounds))
        XCTAssertTrue(MascotOutsideClickPolicy.contains(CGPoint(x: 180, y: 342), in: bounds))
        XCTAssertFalse(MascotOutsideClickPolicy.contains(CGPoint(x: 343, y: 180), in: bounds))
        XCTAssertFalse(MascotOutsideClickPolicy.contains(CGPoint(x: 359, y: 359), in: bounds))
        XCTAssertFalse(MascotOutsideClickPolicy.contains(.zero, in: .zero))
    }
    func testInitialReopenKeepsDashboardHiddenUntilMascotPresentationSettles() {
        let launch = Date(timeIntervalSince1970: 1_000)
        let deadline = launch.addingTimeInterval(1.5)
        XCTAssertFalse(AppReopenPolicy.shouldOpenDashboard(now: launch, suppressUntil: deadline))
        XCTAssertFalse(AppReopenPolicy.shouldOpenDashboard(now: launch.addingTimeInterval(1.4), suppressUntil: deadline))
        XCTAssertTrue(AppReopenPolicy.shouldOpenDashboard(now: deadline, suppressUntil: deadline))
        XCTAssertTrue(AppReopenPolicy.shouldOpenDashboard(now: launch, suppressUntil: nil))
    }
    func testMiniConversationGetsMoreVerticalSpaceThanOtherTools() {
        XCTAssertEqual(MascotMiniTool.conversation.defaultPanelSize.width, 440)
        XCTAssertEqual(MascotMiniTool.conversation.defaultPanelSize.height, 720)
        XCTAssertEqual(MascotMiniTool.reader.defaultPanelSize.height, 320)
    }
    func testConversationFollowPopupFitsVisibleDisplayAfterHeightIncrease() {
        XCTAssertEqual(ConversationMiniChatLayout.preferredSize, CGSize(width: 440, height: 720))

        let display = CGRect(x: 100, y: 40, width: 1440, height: 900)
        let frame = ConversationMiniChatLayout.frame(visibleFrame: display)
        XCTAssertEqual(frame.size, ConversationMiniChatLayout.preferredSize)
        XCTAssertEqual(frame.maxX, display.maxX - 20)
        XCTAssertEqual(frame.minY, display.minY + 40)

        let shortDisplay = CGRect(x: -800, y: 15, width: 430, height: 420)
        let compact = ConversationMiniChatLayout.frame(visibleFrame: shortDisplay)
        XCTAssertEqual(compact.size, shortDisplay.size)
        XCTAssertGreaterThanOrEqual(compact.minX, shortDisplay.minX)
        XCTAssertGreaterThanOrEqual(compact.minY, shortDisplay.minY)
        XCTAssertLessThanOrEqual(compact.maxX, shortDisplay.maxX)
        XCTAssertLessThanOrEqual(compact.maxY, shortDisplay.maxY)
    }
    func testConversationFollowPopupReportsWhetherMicrophoneIsActuallyActive() {
        XCTAssertEqual(ConversationMiniChatStatus.title(active: true, usesMicrophone: false,
            waiting: false, speaking: false), "Nhắn tin · micro đang tắt")
        XCTAssertEqual(ConversationMiniChatStatus.footer(active: true, usesMicrophone: false),
            "Micro đang tắt · Nhắn tin")
        XCTAssertEqual(ConversationMiniChatStatus.title(active: true, usesMicrophone: true,
            waiting: false, speaking: false), "Đang lắng nghe")
        XCTAssertEqual(ConversationMiniChatStatus.footer(active: true, usesMicrophone: true),
            "Micro đang hoạt động · Kết thúc để dừng")
        XCTAssertEqual(ConversationMiniChatStatus.footer(active: false, usesMicrophone: false),
            "Mở đầy đủ để tiếp tục trò chuyện")
    }
    func testTextConversationCanEnableMicrophoneWithoutStartingAnotherSession() {
        XCTAssertTrue(ConversationMicrophonePolicy.canEnable(active: true, usesMicrophone: false,
            waiting: false, changingMicrophone: false, meetingRunning: false))
        XCTAssertFalse(ConversationMicrophonePolicy.canEnable(active: false, usesMicrophone: false,
            waiting: false, changingMicrophone: false, meetingRunning: false))
        XCTAssertFalse(ConversationMicrophonePolicy.canEnable(active: true, usesMicrophone: true,
            waiting: false, changingMicrophone: false, meetingRunning: false))
        XCTAssertFalse(ConversationMicrophonePolicy.canEnable(active: true, usesMicrophone: false,
            waiting: true, changingMicrophone: false, meetingRunning: false))
        XCTAssertFalse(ConversationMicrophonePolicy.canEnable(active: true, usesMicrophone: false,
            waiting: false, changingMicrophone: true, meetingRunning: false))
        XCTAssertFalse(ConversationMicrophonePolicy.canEnable(active: true, usesMicrophone: false,
            waiting: false, changingMicrophone: false, meetingRunning: true))
    }
    func testConversationHeightExpandsAndRestoresPreviousMiniToolHeight() {
        let normal = CGSize(width: 420, height: 340)
        let expanded = MascotMiniToolSizeTransition.applying(
            currentSize: normal, from: .reader, to: .conversation, restoreHeight: nil)
        XCTAssertEqual(expanded.size, CGSize(width: 420, height: 720))
        XCTAssertEqual(expanded.conversationRestoreHeight, 340)

        let restored = MascotMiniToolSizeTransition.applying(
            currentSize: expanded.size, from: .conversation, to: .notebook,
            restoreHeight: expanded.conversationRestoreHeight)
        XCTAssertEqual(restored.size, normal)
        XCTAssertNil(restored.conversationRestoreHeight)
    }
    func testConversationExpandsAndRestoresPreviousUserSizedPanel() {
        let userSize = CGSize(width: 430, height: 680)
        let expanded = MascotMiniToolSizeTransition.applying(
            currentSize: userSize, from: .translation, to: .conversation, restoreHeight: nil)
        XCTAssertEqual(expanded.size, CGSize(width: 430, height: 720))
        XCTAssertEqual(expanded.conversationRestoreHeight, 680)

        let restored = MascotMiniToolSizeTransition.applying(
            currentSize: expanded.size, from: .conversation, to: .settings,
            restoreHeight: expanded.conversationRestoreHeight)
        XCTAssertEqual(restored.size, userSize)
    }
    func testConversationPlacementUsesExtraHeightAndFitsShortDisplays() {
        let mascot = CGRect(x: 520, y: 260, width: 80, height: 100)
        let normalDisplay = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let normalPlacement = MascotMiniToolPlacement.resolve(
            mascotFrame: mascot, screen: normalDisplay,
            preferredSize: MascotMiniTool.conversation.defaultPanelSize)
        XCTAssertEqual(normalPlacement.frame.height, 720)
        XCTAssertGreaterThanOrEqual(normalPlacement.frame.minY, 12)
        XCTAssertLessThanOrEqual(normalPlacement.frame.maxY, normalDisplay.maxY - 12)

        let shortDisplay = CGRect(x: 0, y: 0, width: 1200, height: 420)
        let shortDisplayMascot = CGRect(x: 520, y: 150, width: 80, height: 80)
        let shortPlacement = MascotMiniToolPlacement.resolve(
            mascotFrame: shortDisplayMascot, screen: shortDisplay,
            preferredSize: MascotMiniTool.conversation.defaultPanelSize)
        XCTAssertEqual(shortPlacement.frame.height, shortDisplay.height - 24)
        XCTAssertGreaterThanOrEqual(shortPlacement.frame.minY, 12)
        XCTAssertLessThanOrEqual(shortPlacement.frame.maxY, shortDisplay.maxY - 12)

        let tip = MascotMiniToolPlacement.arrowTip(
            frame: shortPlacement.frame, edge: shortPlacement.arrowEdge,
            offset: shortPlacement.arrowOffset)
        let target: CGPoint
        switch shortPlacement.arrowEdge {
        case .left: target = CGPoint(x: shortDisplayMascot.maxX, y: shortDisplayMascot.midY)
        case .right: target = CGPoint(x: shortDisplayMascot.minX, y: shortDisplayMascot.midY)
        case .top: target = CGPoint(x: shortDisplayMascot.midX, y: shortDisplayMascot.minY)
        case .bottom: target = CGPoint(x: shortDisplayMascot.midX, y: shortDisplayMascot.maxY)
        }
        XCTAssertEqual(hypot(tip.x - target.x, tip.y - target.y), 0, accuracy: 0.01)
    }
    func testMiniToolPlacementFlipsAwayFromScreenEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let centeredMascot = CGRect(x: 625, y: 360, width: 190, height: 186)
        let centered = MascotMiniToolPlacement.resolve(mascotFrame: centeredMascot, screen: screen)
        XCTAssertTrue(centered.arrowEdge == .left || centered.arrowEdge == .right,
                      "When both side placements fit, keep the tool beside the mascot.")
        let centeredGap = centered.arrowEdge == .left
            ? centered.frame.minX - centeredMascot.maxX
            : centeredMascot.minX - centered.frame.maxX
        XCTAssertEqual(centeredGap, 0, accuracy: 0.01)

        let nearRight = MascotMiniToolPlacement.resolve(
            mascotFrame: CGRect(x: 1320, y: 360, width: 90, height: 120), screen: screen)
        XCTAssertLessThanOrEqual(nearRight.frame.maxX, 1320)
        XCTAssertEqual(nearRight.arrowEdge, .right)

        let nearLeft = MascotMiniToolPlacement.resolve(
            mascotFrame: CGRect(x: 20, y: 360, width: 90, height: 120), screen: screen)
        XCTAssertGreaterThanOrEqual(nearLeft.frame.minX, 110)
        XCTAssertEqual(nearLeft.arrowEdge, .left)

        let nearTop = MascotMiniToolPlacement.resolve(
            mascotFrame: CGRect(x: 650, y: 820, width: 90, height: 65), screen: screen)
        XCTAssertLessThan(nearTop.frame.midY, 820)

        for frame in [nearRight.frame, nearLeft.frame, nearTop.frame] {
            XCTAssertGreaterThanOrEqual(frame.minX, 12)
            XCTAssertGreaterThanOrEqual(frame.minY, 12)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX - 12)
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY - 12)
        }
    }
    func testPaperStyleMiniToolSitsBesideMascotWithoutSpeechBubbleAlignmentOffset() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mascot = CGRect(x: 625, y: 360, width: 190, height: 186)
        let placement = MascotMiniToolPlacement.resolve(
            mascotFrame: mascot, screen: screen,
            preferredSize: CGSize(width: 440, height: 320), gap: 12, showArrow: false)
        XCTAssertTrue(placement.arrowEdge == .left || placement.arrowEdge == .right)
        XCTAssertEqual(placement.frame.midY, mascot.midY, accuracy: 0.01)
        let gap = placement.arrowEdge == .left
            ? placement.frame.minX - mascot.maxX
            : mascot.minX - placement.frame.maxX
        XCTAssertEqual(gap, 12, accuracy: 0.01)
    }
    func testMiniToolPlacementUsesVisibleMascotBoundsInsteadOfTransparentWindow() {
        let window = CGRect(x: 900, y: 200, width: 190, height: 186)
        let localArtwork = CGRect(x: 58, y: 34, width: 74, height: 82)
        let anchor = MascotMiniToolPlacement.visualAnchor(windowFrame: window, localBounds: localArtwork)
        XCTAssertEqual(anchor, CGRect(x: 958, y: 270, width: 74, height: 82))

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let placement = MascotMiniToolPlacement.resolve(mascotFrame: anchor, screen: screen)
        XCTAssertEqual(placement.arrowEdge, .right)
        XCTAssertEqual(anchor.minX - placement.frame.maxX, 0, accuracy: 0.01)
        XCTAssertEqual(placement.arrowOffset, anchor.midY - placement.frame.minY, accuracy: 0.01)
        let tip = MascotMiniToolPlacement.arrowTip(frame: placement.frame, edge: placement.arrowEdge, offset: placement.arrowOffset)
        XCTAssertEqual(tip.x, anchor.minX, accuracy: 0.01)
        XCTAssertEqual(tip.y, anchor.midY, accuracy: 0.01)

        let edgeCases: [(CGRect, CGPoint)] = [
            (CGRect(x: 1320, y: 360, width: 90, height: 120), CGPoint(x: 1365, y: 420)),
            (CGRect(x: 20, y: 360, width: 90, height: 120), CGPoint(x: 65, y: 420)),
            (CGRect(x: 650, y: 820, width: 90, height: 65), CGPoint(x: 695, y: 852.5))
        ]
        for (target, center) in edgeCases {
            let placement = MascotMiniToolPlacement.resolve(mascotFrame: target, screen: screen)
            let tip = MascotMiniToolPlacement.arrowTip(frame: placement.frame, edge: placement.arrowEdge, offset: placement.arrowOffset)
            let targetPoint: CGPoint
            switch placement.arrowEdge {
            case .left: targetPoint = CGPoint(x: target.maxX, y: center.y)
            case .right: targetPoint = CGPoint(x: target.minX, y: center.y)
            case .top: targetPoint = CGPoint(x: center.x, y: target.minY)
            case .bottom: targetPoint = CGPoint(x: center.x, y: target.maxY)
            }
            XCTAssertEqual(hypot(tip.x - targetPoint.x, tip.y - targetPoint.y), 0, accuracy: 0.01)
        }
    }
    func testSpeechCardAnchorsToVisibleMascotArtworkNotTransparentLauncherFrame() {
        let window = CGRect(x: 0, y: 150, width: 190, height: 186)
        let artwork = CGRect(x: 52, y: 24, width: 88, height: 132)
        let anchor = MascotMiniToolPlacement.visualAnchor(windowFrame: window, localBounds: artwork)
        let screen = CGRect(x: 0, y: 0, width: 1094, height: 488)
        let placement = MascotSpeechCardPlacement.resolve(
            anchor: anchor, screen: screen, size: CGSize(width: 340, height: 160))

        XCTAssertTrue(placement.onRight)
        XCTAssertEqual(placement.frame.minX, anchor.maxX + 8, accuracy: 0.01)
        XCTAssertEqual(placement.frame.midY, anchor.midY, accuracy: 0.01)

        let nearRightScreen = CGRect(x: 0, y: 0, width: 1094, height: 488)
        let nearRightAnchor = CGRect(x: 930, y: 180, width: 100, height: 140)
        let flipped = MascotSpeechCardPlacement.resolve(
            anchor: nearRightAnchor, screen: nearRightScreen, size: CGSize(width: 340, height: 160))
        XCTAssertFalse(flipped.onRight)
        XCTAssertEqual(flipped.frame.maxX, nearRightAnchor.minX - 8, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(flipped.frame.minX, nearRightScreen.minX + 10)
        XCTAssertLessThanOrEqual(flipped.frame.maxX, nearRightScreen.maxX - 10)
    }
    func testSpeechCardKeepsPointerOutsideArtworkWhenBodyTargetIsOffCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1094, height: 488)
        let body = CGPoint(x: 100, y: 180)
        let artwork = CGRect(x: 60, y: 100, width: 100, height: 160)
        let placement = MascotSpeechCardPlacement.resolve(
            anchor: artwork, target: body, screen: screen, size: CGSize(width: 340, height: 160))

        XCTAssertTrue(placement.onRight)
        XCTAssertEqual(placement.frame.minX, artwork.maxX + 8, accuracy: 0.01)
        XCTAssertEqual(placement.frame.midY, body.y, accuracy: 0.01)
    }
    func testSpeechPointerTracksMascotBodyWhenCardClampsAtScreenEdge() {
        let window = CGRect(x: 100, y: 0, width: 190, height: 186)
        let artwork = CGRect(x: 52, y: 20, width: 88, height: 140)
        let body = MascotMiniToolPlacement.bodyAnchor(
            windowFrame: window, localBounds: artwork, verticalFraction: 0.64)
        XCTAssertEqual(body.x, 196, accuracy: 0.01)
        XCTAssertEqual(body.y, 76.4, accuracy: 0.01)

        let centeredPerson = MascotMiniToolPlacement.bodyAnchor(
            windowFrame: window, localBounds: artwork)
        XCTAssertEqual(centeredPerson.y, 59.6, accuracy: 0.01)
        XCTAssertLessThan(centeredPerson.y, body.y)
        let pendingBounds = MascotMiniToolPlacement.bodyAnchor(windowFrame: window, localBounds: nil)
        XCTAssertEqual(pendingBounds.y, window.maxY - window.height * 0.76, accuracy: 0.01)

        let screen = CGRect(x: 0, y: 0, width: 1094, height: 244)
        let anchor = MascotMiniToolPlacement.visualAnchor(windowFrame: window, localBounds: artwork)
        let placement = MascotSpeechCardPlacement.resolve(
            anchor: anchor, target: body, screen: screen, size: CGSize(width: 340, height: 160))
        XCTAssertEqual(placement.frame.minY, 10, accuracy: 0.01)
        XCTAssertGreaterThan(placement.arrowY, 0.5)

        let localTipY = placement.frame.height * placement.arrowY
        let tipScreenY = placement.frame.maxY - localTipY
        XCTAssertEqual(tipScreenY, body.y, accuracy: 0.01)
    }
    func testMiniToolArrowTracksMeasuredMascotAcrossOrbitResize() {
        let collapsedWindow = CGRect(x: 900, y: 200, width: 190, height: 186)
        let collapsedArtwork = CGRect(x: 58, y: 62, width: 74, height: 82)
        let collapsedAnchor = MascotMiniToolPlacement.visualAnchor(windowFrame: collapsedWindow,
                                                                    localBounds: collapsedArtwork)

        // The orbit enlarges and repositions its transparent launcher window,
        // but the collapsed mascot artwork remains at the same screen point.
        let expandedWindow = CGRect(x: 815, y: 68, width: 360, height: 360)
        let expandedArtwork = CGRect(x: 143, y: 104, width: 74, height: 82)
        let expandedAnchor = MascotMiniToolPlacement.visualAnchor(windowFrame: expandedWindow,
                                                                  localBounds: expandedArtwork)
        XCTAssertEqual(collapsedAnchor, expandedAnchor)
        XCTAssertEqual(collapsedAnchor, CGRect(x: 958, y: 242, width: 74, height: 82))

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for anchor in [collapsedAnchor, expandedAnchor] {
            let placement = MascotMiniToolPlacement.resolve(mascotFrame: anchor, screen: screen)
            let tip = MascotMiniToolPlacement.arrowTip(frame: placement.frame,
                                                       edge: placement.arrowEdge,
                                                       offset: placement.arrowOffset)
            switch placement.arrowEdge {
            case .left, .right: XCTAssertEqual(tip.y, anchor.midY, accuracy: 0.01)
            case .top, .bottom: XCTAssertEqual(tip.x, anchor.midX, accuracy: 0.01)
            }
        }
    }
    func testMiniToolArrowStaysAlignedWhenPanelIsClampedNearDisplayEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mascots = [
            CGRect(x: 1310, y: 770, width: 90, height: 100),
            CGRect(x: 20, y: 770, width: 90, height: 100),
            CGRect(x: 1310, y: 30, width: 90, height: 100),
            CGRect(x: 20, y: 30, width: 90, height: 100)
        ]
        for mascot in mascots {
            let placement = MascotMiniToolPlacement.resolve(mascotFrame: mascot, screen: screen)
            let overlap = placement.frame.intersection(mascot)
            XCTAssertLessThanOrEqual(max(0, overlap.width) * max(0, overlap.height), 0.01,
                                     "The panel may touch the mascot at its tail tip, but its content must not overlap it.")
            let tip = MascotMiniToolPlacement.arrowTip(frame: placement.frame,
                                                       edge: placement.arrowEdge,
                                                       offset: placement.arrowOffset)
            let expected: CGPoint
            switch placement.arrowEdge {
            case .left: expected = CGPoint(x: mascot.maxX, y: mascot.midY)
            case .right: expected = CGPoint(x: mascot.minX, y: mascot.midY)
            case .top: expected = CGPoint(x: mascot.midX, y: mascot.minY)
            case .bottom: expected = CGPoint(x: mascot.midX, y: mascot.maxY)
            }
            XCTAssertEqual(hypot(tip.x - expected.x, tip.y - expected.y), 0, accuracy: 0.01,
                           "Tail tip should meet the mascot anchor without a visible gap.")
        }
    }
    func testMiniToolBubbleKeepsSeamlessTailWithinOuterBounds() {
        let rect = CGRect(x: 0, y: 0, width: 460, height: 350)
        for edge in [MascotMiniToolArrowEdge.left, .right, .top, .bottom] {
            let shape = MascotMiniToolBubble(edge: edge, offset: edge == .top || edge == .bottom ? 230 : 175)
            let path = shape.path(in: rect)
            let bounds = path.boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.01)
            XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.01)
            XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.01)
            XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.01)
            switch edge {
            case .left: XCTAssertEqual(bounds.minX, rect.minX, accuracy: 0.01)
            case .right: XCTAssertEqual(bounds.maxX, rect.maxX, accuracy: 0.01)
            case .top: XCTAssertEqual(bounds.minY, rect.minY, accuracy: 0.01)
            case .bottom: XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 0.01)
            }
            XCTAssertFalse(path.isEmpty)
        }
    }
    func testInsetBorderKeepsTailCenteredAndAlignedToNonZeroBounds() {
        let rect = CGRect(x: 17, y: 29, width: 460, height: 350)
        for edge in [MascotMiniToolArrowEdge.left, .right, .top, .bottom] {
            let shape = MascotMiniToolBubble(edge: edge, offset: edge == .top || edge == .bottom ? 230 : 175)
            let fillTip = shape.tailTip(in: rect)
            let borderTip = shape.insetted(by: 0.5).tailTip(in: rect)
            switch edge {
            case .left:
                XCTAssertEqual(borderTip.x, fillTip.x + 0.5, accuracy: 0.01)
                XCTAssertEqual(borderTip.y, fillTip.y, accuracy: 0.01)
            case .right:
                XCTAssertEqual(borderTip.x, fillTip.x - 0.5, accuracy: 0.01)
                XCTAssertEqual(borderTip.y, fillTip.y, accuracy: 0.01)
            case .top:
                XCTAssertEqual(borderTip.x, fillTip.x, accuracy: 0.01)
                XCTAssertEqual(borderTip.y, fillTip.y + 0.5, accuracy: 0.01)
            case .bottom:
                XCTAssertEqual(borderTip.x, fillTip.x, accuracy: 0.01)
                XCTAssertEqual(borderTip.y, fillTip.y - 0.5, accuracy: 0.01)
            }
        }
    }
    func testSubtitleFollowsMascotTranslationAndClampsToScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let head = CGRect(x: 45, y: 90, width: 100, height: 90)
        let mascot = CGRect(x: 500, y: 150, width: 190, height: 186)
        let before = MascotSubtitlePlacement.resolve(mascotFrame: mascot, headBounds: head, screen: screen)
        let after = MascotSubtitlePlacement.resolve(mascotFrame: mascot.offsetBy(dx: 130, dy: 80), headBounds: head, screen: screen)
        XCTAssertEqual(after.frame.minX - before.frame.minX, 130, accuracy: 0.01)
        XCTAssertEqual(after.frame.minY - before.frame.minY, 80, accuracy: 0.01)
        XCTAssertEqual(after.arrowX, before.arrowX)
        XCTAssertTrue(after.arrowBelow)
        let edge = MascotSubtitlePlacement.resolve(mascotFrame: CGRect(x: 1200, y: 710, width: 190, height: 186), headBounds: head, screen: screen)
        XCTAssertFalse(edge.arrowBelow)
        XCTAssertLessThanOrEqual(edge.frame.maxX, screen.maxX - 8)
        XCTAssertLessThanOrEqual(edge.frame.maxY, screen.maxY - 8)
        XCTAssertEqual(edge.frame.minX + edge.arrowX, 1295, accuracy: 0.01)
    }

    func testQuickSubtitleArrowRemainsAnchoredAfterBorderInsetAndHorizontalClamping() {
        let rect = CGRect(x: 17, y: 29, width: 480, height: 126)
        for arrowBelow in [false, true] {
            let shape = MascotSubtitleBubble(arrowX: 240, arrowBelow: arrowBelow)
            let fillTip = shape.tailTip(in: rect)
            let strokeTip = shape.insetted(by: 0.5).tailTip(in: rect)
            XCTAssertEqual(strokeTip.x, fillTip.x, accuracy: 0.01)
            XCTAssertEqual(strokeTip.y, arrowBelow ? fillTip.y - 0.5 : fillTip.y + 0.5, accuracy: 0.01)
        }

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mascot = CGRect(x: 0, y: 250, width: 100, height: 150)
        let head = CGRect(x: 25, y: 70, width: 50, height: 60)
        let placement = MascotSubtitlePlacement.resolve(mascotFrame: mascot, headBounds: head, screen: screen)
        XCTAssertEqual(placement.frame.minX + placement.arrowX, mascot.minX + head.midX, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(placement.arrowX, 24)
        XCTAssertLessThanOrEqual(placement.arrowX, placement.frame.width - 24)
    }

    func testCustomMascotBubbleBordersInsetWithoutBreakingTheirTails() {
        let rect = CGRect(x: 17, y: 29, width: 360, height: 180)

        for tailOnLeft in [false, true] {
            let shape = MascotBoardBubbleShape(tailOnLeft: tailOnLeft)
            let fillTip = shape.tailTip(in: rect)
            let borderTip = shape.insetted(by: 0.5).tailTip(in: rect)
            XCTAssertEqual(borderTip.x, fillTip.x + (tailOnLeft ? 0.5 : -0.5), accuracy: 0.01)
            XCTAssertEqual(borderTip.y, fillTip.y, accuracy: 0.01)
            XCTAssertTrue(shape.insetted(by: 0.5).path(in: rect).boundingRect.midX.isFinite)
        }

        let tooltip = MascotTooltipBubble()
        let tooltipTip = tooltip.tailTip(in: rect)
        let insetTooltipTip = tooltip.insetted(by: 0.5).tailTip(in: rect)
        XCTAssertEqual(insetTooltipTip.x, tooltipTip.x, accuracy: 0.01)
        XCTAssertEqual(insetTooltipTip.y, tooltipTip.y - 0.5, accuracy: 0.01)
        XCTAssertTrue(tooltip.insetted(by: 0.5).path(in: rect).boundingRect.midY.isFinite)
    }

    func testThoughtCloudBorderInsertsInsideItsBounds() {
        let rect = CGRect(x: 11, y: 23, width: 172, height: 64)
        let shape = ThoughtCloudShape()
        let outer = shape.path(in: rect).boundingRect
        let inset = shape.insetted(by: 0.6).path(in: rect).boundingRect
        XCTAssertGreaterThan(inset.minX, outer.minX)
        XCTAssertLessThan(inset.maxX, outer.maxX)
        XCTAssertGreaterThan(inset.minY, outer.minY)
        XCTAssertLessThan(inset.maxY, outer.maxY)
    }

}
