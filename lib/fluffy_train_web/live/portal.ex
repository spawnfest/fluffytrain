defmodule FluffyTrainWeb.Portal do
  use FluffyTrainWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
      <div class="flex items-center justify-center h-screen space-x-40">
        <a href="/ei">
          <img src="/images/Logo_Concept_2.png" class="top-10 h-50 w-50 object-cover hover:shadow-lg hover:border-black transition duration-500 ease-in-out">
        </a>
        <a href="/eai">
        <img src="/images/Logo_Self_Healing.png" class="object-cover h-50 w-50 hover:shadow-lg hover:border-gray-500 transition duration-500 ease-in-out">
        </a>
      </div>
    """
  end
end
