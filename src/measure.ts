import { closeMainWindow, getPreferenceValues } from "@raycast/api";
import { inspect } from "swift:../swift/DesignRuler";

interface Preferences {
  hideHintBar: boolean;
  corrections: string;
}

export default async function Command() {
  await closeMainWindow();
  const { hideHintBar, corrections } = getPreferenceValues<Preferences>();
  await inspect(hideHintBar ?? false, corrections ?? "smart");
}
