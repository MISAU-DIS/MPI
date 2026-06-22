// Action Cable provides the framework to deal with WebSockets in Rails.
// You can generate new channels where WebSocket features live using the `bin/rails generate channel` command.

import { createConsumer } from "@rails/actioncable"

const protocol = "ws"
const host = window.location.host
const cableUrl = `${protocol}://${host}/v1/cable`
// export default createConsumer(cableUrl)
export default createConsumer("/v1/cable")
