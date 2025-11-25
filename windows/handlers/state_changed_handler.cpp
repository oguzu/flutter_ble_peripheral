#include "state_changed_handler.h"

#include <flutter/encodable_value.h>

namespace flutter_ble_peripheral {
namespace handlers {

    StateChangedHandler::StateChangedHandler()
        : current_state_(PeripheralState::Idle), event_sink_(nullptr) {}

    StateChangedHandler::~StateChangedHandler() {}

    void StateChangedHandler::PublishPeripheralState(PeripheralState state) {
        current_state_ = state;
        if (event_sink_) {
            event_sink_->Success(flutter::EncodableValue(static_cast<int>(state)));
        }
    }

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
        StateChangedHandler::OnListenInternal(
            const flutter::EncodableValue* arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
        event_sink_ = std::move(events);
        // Immediately publish current state when listener is attached
        PublishPeripheralState(current_state_);
        return nullptr;
    }

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
        StateChangedHandler::OnCancelInternal(const flutter::EncodableValue* arguments) {
        event_sink_ = nullptr;
        return nullptr;
    }

}  // namespace handlers
}  // namespace flutter_ble_peripheral
