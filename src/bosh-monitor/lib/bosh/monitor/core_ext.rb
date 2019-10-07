module Kernel
  def pluralize(number, singular, plural = nil)
    plural ||= "#{singular}s"
    number == 1 ? "1 #{singular}" : "#{number} #{plural}"
  end
end
