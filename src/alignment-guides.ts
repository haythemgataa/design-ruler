import { closeMainWindow, getPreferenceValues } from "@raycast/api";
import { alignmentGuides } from "swift:../swift/DesignRuler";

interface Preferences {
  showHintBar: boolean;
}

export default async function Command() {
  await closeMainWindow();
  const { showHintBar } = getPreferenceValues<Preferences>();
  await alignmentGuides(showHintBar ?? true);
}
