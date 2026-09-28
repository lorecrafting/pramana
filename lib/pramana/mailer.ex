defmodule Pramana.Mailer do
  use Swoosh.Mailer, otp_app: :pramana

  def delivery_ready?, do: Application.get_env(:pramana, :mail_delivery_ready, false)
end
