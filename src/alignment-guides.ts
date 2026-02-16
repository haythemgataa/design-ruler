import { closeMainWindow, getPreferenceValues } from "@raycast/api";
import { alignmentGuides } from "swift:../swift/Ruler";

interface Preferences {
  hideHintBar: boolean;
}

export default async function Command() {
  await closeMainWindow();
  const { hideHintBar } = getPreferenceValues<Preferences>();
  await alignmentGuides(hideHintBar ?? false);
}
