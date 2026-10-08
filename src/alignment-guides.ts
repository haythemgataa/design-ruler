import { closeMainWindow, environment, getPreferenceValues } from "@raycast/api";
import { alignmentGuides } from "swift:../swift/DesignRuler";

interface Preferences {
  showHintBar: boolean;
  remembersGuideStyle: boolean;
}

export default async function Command() {
  await closeMainWindow();
  const { showHintBar, remembersGuideStyle } = getPreferenceValues<Preferences>();
  await alignmentGuides(showHintBar ?? true, remembersGuideStyle ?? false, environment.supportPath);
}
