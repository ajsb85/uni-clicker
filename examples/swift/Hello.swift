import CBoard

private func writeBanner() {
    let message: StaticString = "Hello, UNI Clicker from Embedded Swift!\r\n"
    board_uart_write(message.utf8Start, UInt32(message.utf8CodeUnitCount))
}

@_cdecl("uni_swift_main")
public func helloUni() -> Never {
    board_init()
    writeBanner()

    var edges: UInt32 = 0
    while true {
        board_wait_ms(500)
        edges &+= 1
        board_set_led(edges)
        if edges & 1 == 0 {
            writeBanner()
        }
    }
}
