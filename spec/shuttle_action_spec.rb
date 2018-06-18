describe Fastlane::Actions::ShuttleAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The shuttle plugin is working!")

      Fastlane::Actions::ShuttleAction.run(nil)
    end
  end
end
