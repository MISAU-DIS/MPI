module Api
  module V1
    class MonitoringController < ApplicationController
      def show
        render json: MonitoringService.report(days: params[:days], current_user: current_user)
      end
    end
  end
end
