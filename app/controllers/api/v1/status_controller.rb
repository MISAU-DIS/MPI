module Api
  module V1
    class StatusController < ApplicationController
      skip_before_action :authenticate_request

      def index
        render json: {
          status: 'ok',
          timestamp: Time.current.iso8601,
          environment: Rails.env
        }, status: :ok
      end
    end
  end
end