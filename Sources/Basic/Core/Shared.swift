//
//  Shared.swift
//  ATMetalBand
//
//  Created by Condy on 2022/2/17.
//

import Foundation
// ObjectiveC import might not be needed anymore if associated objects are gone.
// import ObjectiveC

public actor Shared {
    
    public static let shared = Shared()
    
    private var _device: Device?
    private var deviceInitializationTask: Task<Device, Never>? // Device.init() fatalErrors, doesn't throw

    private init() { } // Private initializer for singleton pattern

    public func getInitializedDevice() async -> Device { // No 'throws' if Device.init() doesn't throw
        if let existingDevice = _device {
            return existingDevice
        }
        if let runningTask = deviceInitializationTask {
            return await runningTask.value // No 'try' if Task is Task<Device, Never>
        }

        let newTask = Task<Device, Never> { // Task produces Device, never throws
            let newDevice = await Device() // Device.init() is async
            return newDevice
        }
        self.deviceInitializationTask = newTask

        let device = await newTask.value
        self._device = device // Store after successful initialization
        self.deviceInitializationTask = nil // Clear successful task
        return device
    }

    /// 释放`Device`资源
    /// 考虑到`Device`当中存在蛮多比较消耗性能的对象，所以设计单例全局使用
    /// 一旦不再使用Metal之后，就调此方法将之释放掉
    ///
    /// Release the Device resource
    /// Considering that there are quite a lot of performance-consuming objects in `Device`, design a singleton for global use.
    /// Once Metal is no longer used, call this method to release it.
    public func deinitDevice() { // Remains synchronous
        _device = nil
        deviceInitializationTask?.cancel()
        deviceInitializationTask = nil
    }
    
    /// 是否已经初始化`Device`资源
    /// Whether the Device resource has been initialized.
    public func hasInitializedDevice() -> Bool {
        return _device != nil
    }
    
    /// 提前加载`Device`资源
    public func advanceSetupDevice() {
        Task { // Creates a new Task to call the async getInitializedDevice
            _ = await getInitializedDevice() // Result is ignored, just triggers initialization
        }
    }
}
