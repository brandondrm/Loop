//
//  PumpDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import MinimedKit
import RileyLinkKit

class PumpDataManager {
    enum State {
        case NeedsConfiguration
        case Ready(manager: RileyLinkManager)
    }

    // MARK: - Observed state

    var rileyLinkManager: RileyLinkManager? {
        switch state {
        case .Ready(manager: let manager):
            return manager
        case .NeedsConfiguration:
            return nil
        }
    }

    var rileyLinkManagerObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkManagerObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    var rileyLinkDeviceObserver: AnyObject? {
        willSet {
            if let observer = rileyLinkDeviceObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    func receivedRileyLinkManagerNotification(note: NSNotification) {
        NSNotificationCenter.defaultCenter().postNotificationName(note.name, object: self, userInfo: note.userInfo)
    }

    func receivedRileyLinkPacketNotification(note: NSNotification) {
        if let
            device = note.object as? RileyLinkDevice,
            packet = note.userInfo?[RileyLinkDevicePacketKey] as? MinimedPacket where packet.valid == true,
            let message = PumpMessage(rxData: packet.messageData),
            pumpID = pumpID
        {
            switch message.packetType {
            case .MySentry:
                // Reply to PumpStatus packets with an ACK
                let ack = PumpMessage(packetType: .MySentry, address: pumpID, messageType: .PumpStatusAck, messageBody: MySentryAckMessageBody(mySentryID: [0x00, 0x08, 0x88], responseMessageTypes: [message.messageType]))
                device.sendMessageData(ack.txData)
            default:
                break
            }
        }
    }

    func connectToRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.insert(device.peripheral.identifier.UUIDString)

        rileyLinkManager?.connectDevice(device)
    }

    func disconnectFromRileyLink(device: RileyLinkDevice) {
        connectedPeripheralIDs.remove(device.peripheral.identifier.UUIDString)

        rileyLinkManager?.disconnectDevice(device)
    }

    // MARK: - Managed state

    var state: State = .NeedsConfiguration {
        willSet {
            switch newValue {
            case .Ready(manager: let manager):
                rileyLinkManagerObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: manager, queue: nil) { [weak self = self] (note) -> Void in
                    self?.receivedRileyLinkManagerNotification(note)
                }

                rileyLinkDeviceObserver = NSNotificationCenter.defaultCenter().addObserverForName(RileyLinkDeviceDidReceivePacketNotification, object: nil, queue: nil, usingBlock: { [weak self = self] (note) -> Void in
                    self?.receivedRileyLinkPacketNotification(note)
                })

            case .NeedsConfiguration:
                rileyLinkManagerObserver = nil
                rileyLinkDeviceObserver = nil
            }
        }
    }

    var connectedPeripheralIDs: Set<String> {
        didSet {
            NSUserDefaults.standardUserDefaults().connectedPeripheralIDs = Array(connectedPeripheralIDs)
        }
    }

    var pumpID: String? {
        didSet {
            if pumpID?.characters.count != 6 {
                pumpID = nil
            }

            switch state {
            case .NeedsConfiguration where pumpID != nil:
                state = .Ready(manager: RileyLinkManager(pumpID: pumpID!, autoconnectIDs: connectedPeripheralIDs))
            case .Ready(manager: _) where pumpID == nil:
                state = .NeedsConfiguration
            case .NeedsConfiguration, .Ready:
                break
            }

            NSUserDefaults.standardUserDefaults().pumpID = pumpID
        }
    }

    static let sharedManager = PumpDataManager()

    init() {
        connectedPeripheralIDs = Set(NSUserDefaults.standardUserDefaults().connectedPeripheralIDs)
    }

    deinit {
        // Unregistering observers necessary in iOS 8 only
        rileyLinkManagerObserver = nil
        rileyLinkDeviceObserver = nil
    }
}