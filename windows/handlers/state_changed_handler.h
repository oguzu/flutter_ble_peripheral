#ifndef FLUTTER_PLUGIN_STATE_CHANGED_HANDLER_H_
#define FLUTTER_PLUGIN_STATE_CHANGED_HANDLER_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "../models/peripheral_state.h"

namespace flutter_ble_peripheral {
namespace handlers {

    using models::PeripheralState;

    class StateChangedHandler : public flutter::StreamHandler<flutter::EncodableValue> {
    public:
        StateChangedHandler();
        virtual ~StateChangedHandler();

        // Disallow copy and assign.
        StateChangedHandler(const StateChangedHandler&) = delete;
        StateChangedHandler& operator=(const StateChangedHandler&) = delete;

        // Publish peripheral state change to Flutter
        void PublishPeripheralState(PeripheralState state);

        // Get current state
        PeripheralState GetState() const { return current_state_; }

    protected:
        // StreamHandler implementation
        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
            OnListenInternal(
                const flutter::EncodableValue* arguments,
                std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override;

        std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
            OnCancelInternal(const flutter::EncodableValue* arguments) override;

    private:
        PeripheralState current_state_;
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
    };

}  // namespace handlers
}  // namespace flutter_ble_peripheral

#endif  // FLUTTER_PLUGIN_STATE_CHANGED_HANDLER_H_
