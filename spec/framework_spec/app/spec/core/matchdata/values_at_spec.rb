require File.dirname(File.join(__rhoGetCurrentDir(), __FILE__)) + '/../../spec_helper'

describe "MatchData#values_at" do
  it "returns an array of the matching value" do
    /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(0, 2, -2).should == ["HX1138", "X", "113"]
  end
end
