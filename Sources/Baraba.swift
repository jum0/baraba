//
// Baraba.swift
//
// Copyright (c) 2020 Soojin Ro (https://github.com/nsoojin)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import UIKit
import QuartzCore

/**
 The main object that you use to add auto-scrolling to a scroll view.
*/
public class Baraba: NSObject {
    
    /**
     Returns a boolean value indicating whether a given configuration is supported by the device.
    */
    public static func isConfigurationSupported(_ configuration: BarabaConfiguration) -> Bool {
        return configuration.trackerType.isSupported
    }
    
    /**
     The scroll view that will be auto-scrolled when user is looking at the device.
    */
    public weak var scrollView: UIScrollView? {
        didSet {
            if let scrollView = scrollView {
                addScrollViewObservers(scrollView)
            } else {
                removeScrollViewObservers()
            }
        }
    }
    
    /**
     The delegate for the Baraba object.
    */
    public weak var delegate: BarabaDelegate?
    
    /**
     A Boolean value that indicates whether this Baraba object is active and tracking user's face.
     
     This is a read-only property. If you want to make Baraba active, call `resume()` on the receiver.
    */
    public private(set) var isActive: Bool = false
    
    /**
     A Boolean value that indicates whether the scroll view is being auto-scrolled. Read-only.
    */
    public var isScrolling: Bool {
        displayLink?.isPaused == false
    }
    
    /**
     The speed in which to auto-scroll the scroll view. Represented in points per second. Default value is `200.0`.
     
     The minimum scroll speed is 60 points per second. Negative value is not supported.
    */
    public var speed: Double {
        set {
            _speed = newValue
        }
        get {
            _speed
        }
    }
    
    /**
     The duration of pause in seconds, after user finishes dragging the scroll view. Default value is `2.0`.
     
     After this amount of duration, auto-scrolling resumes.
    */
    public var pauseDuration: TimeInterval {
        set {
            _pauseDuration = newValue
            suspendDebouncer = Debouncer(delay: _pauseDuration)
        }
        get {
            _pauseDuration
        }
    }
    
    /**
     Starts the tracking of user's face for auto-scrolling.
     
     If the object fails to resume, `func baraba(_ baraba: Baraba, didFailWithError error: Error)` will be called on the delegate.
    */
    public func resume() {
        if scrollView == nil {
            print("Baraba(\(self)) failed to resume. Its scrollView property is nil. Please designate a scrollView before calling resume()")
            return
        }
        
        if isActive {
            print("Baraba is already running.")
            return
        }
        
        print("resume baraba")
        setupDisplayLink()
        tracker.resume()
        isActive = true
    }
    
    /**
     Pauses the tracking of user's face.
     
     Call this method when you no longer need to track user's face. For example, inside `func viewWillDisappear(_ animated:)` of a view controller.
    */
    public func pause() {
        if isActive {
            print("pause baraba")
            isActive = false
            isSuspended = false
            isFacing = false
            invalidateDisplayLink()
            tracker.pause()
        }
    }
    
    /**
     Creates a new Baraba object with the specified configuration.
     
     Before initializing, you can check if the device supports the configuration by looking at `isSupported` property of a configuration object.
     
     Using an unsupported configuration will invoke `func baraba(_ baraba: Baraba, didFailWithError error: Error)` call to the delegate.
     
     - Parameters:
        - configuration: A configuration object that specifies which feature to use to track user's face.
    */
    public init(configuration: BarabaConfiguration) {
        tracker = configuration.trackerType.init()
        logger = Baraba.makeLogger()
        workQueue = DispatchQueue(label: "\(Constant.bundleIdentifier).queue", qos: .userInitiated, autoreleaseFrequency: .workItem)
        suspendDebouncer = Debouncer(delay: 0)
        
        super.init()
        
        suspendDebouncer = Debouncer(delay: _pauseDuration)
        tracker.delegate = self
    }

    @objc
    internal func scroll(displayLink: CADisplayLink) {
        logger(displayLink.timestamp)
        
        guard let scrollView = scrollView, shouldScroll else {
            return
        }
        
        let actualFramesPerSecond = 1 / (displayLink.targetTimestamp - displayLink.timestamp)
        let scrollOffset = ceil(speed / actualFramesPerSecond)
        let target = CGPoint(x: 0, y: scrollView.contentOffset.y + CGFloat(scrollOffset))
        if target.y + scrollView.bounds.height <= scrollView.contentSize.height + scrollView.adjustedContentInset.bottom {
            scrollView.contentOffset = target
        }
    }
    
    private func addScrollViewObservers(_ scrollView: UIScrollView) {
        contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new, .old], changeHandler: observeContentOffset(_:_:))
    }
    
    private func removeScrollViewObservers() {
        contentOffsetObservation = nil
    }

    private func observeContentOffset(_ scrollView: UIScrollView, _ change: NSKeyValueObservedChange<CGPoint>) {
        if scrollView.isDragging, isActive {
            if isSuspended == false {
                isSuspended = true
            }
            
            suspendDebouncer.schedule {
                self.resumeScroll()
            }
        }
    }
    
    private func resumeScroll() {
        if scrollView?.isDragging == false {
            isSuspended = false
        } else {
            suspendDebouncer.schedule {
                self.resumeScroll()
            }
        }
    }
    
    private func setupDisplayLink() {
        let displayLink = CADisplayLink(target: self, selector: #selector(scroll))
        displayLink.add(to: .main, forMode: .default)
        displayLink.isPaused = true
        
        self.displayLink = displayLink
    }
    
    private func invalidateDisplayLink() {
        displayLink?.invalidate()
    }
    
    private func evaluate() {
        print("evaluate in \(Thread.isMainThread ? "main" : "bg")")
        guard let displayLink = displayLink, isActive else {
            return
        }
        
        if shouldScroll == true && displayLink.isPaused == true {
            displayLink.isPaused = false
            DispatchQueue.main.async { self.delegate?.barabaDidStartScrolling(self) }
        } else if shouldScroll == false && displayLink.isPaused == false {
            displayLink.isPaused = true
            DispatchQueue.main.async { self.delegate?.barabaDidStopScrolling(self) }
        }
    }
    
    private var shouldScroll: Bool {
        return isFacing && isActive && isSuspended == false
    }
    
    private var isFacing: Bool = false {
        didSet {
            workQueue.async { self.evaluate() }
        }
    }
    
    private var isSuspended: Bool = false {
        didSet {
            workQueue.async { self.evaluate() }
        }
    }
    
    @Minimum(min: 60)
    private var _speed: Double = 200.0
    
    @Minimum(min: 0)
    private var _pauseDuration: Double = 2.0
    
    private weak var displayLink: CADisplayLink?
    private var logger: (CFTimeInterval) -> Void
    private var contentOffsetObservation: NSKeyValueObservation?
    private var suspendDebouncer: Debouncer
    private let tracker: FaceTracker
    private let workQueue: DispatchQueue
}

extension Baraba: FaceTrackerDelegate {
    internal func trackerDidStartTrackingFace(_ tracker: FaceTracker) {
        print("------- facing content")
        isFacing = true
    }
    
    internal func trackerDidEndTrackingFace(_ tracker: FaceTracker) {
        print("------- looking away")
        isFacing = false
    }
    
    internal func trackerWasInterrupted(_ tracker: FaceTracker) {
        print("------- interrupted")
        isSuspended = true
    }
    
    internal func trackerInterruptionEnded(_ tracker: FaceTracker) {
        print("------- interruption ended")
        isSuspended = false
    }
}

internal extension Baraba {
    private static func makeLogger() -> (CFTimeInterval) -> Void {
            var lastLoggedTime = 0
            return { interval in
                let second = Int(floor(interval))
                
                if lastLoggedTime + 1 <= second {
                    lastLoggedTime = second
    //                print("scrolling...")
                }
            }
        }
}
