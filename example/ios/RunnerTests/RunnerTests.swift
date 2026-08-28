import Flutter
import UIKit
import XCTest

// If your plugin has been explicitly set to "type: .dynamic" in the Package.swift,
// you will need to add your plugin as a dependency of RunnerTests within Xcode.

@testable import activelook_sdk

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  func testUnknownMethodIsNotImplemented() {
    let plugin = ActivelookSdkPlugin()

    let call = FlutterMethodCall(methodName: "notARealMethod", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue((result as AnyObject) === (FlutterMethodNotImplemented as AnyObject))
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testDrawCommandWithoutConnectedGlassesErrorsNotConnected() {
    let plugin = ActivelookSdkPlugin()

    let call = FlutterMethodCall(methodName: "clear", arguments: [:])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      guard let error = result as? FlutterError else {
        XCTFail("expected a FlutterError when no glasses are connected")
        return
      }
      XCTAssertEqual(error.code, "NOT_CONNECTED")
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

}
