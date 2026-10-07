import { closeMainWindow, getPreferenceValues } from "@raycast/api";
import { inspect } from "swift:../swift/DesignRuler";

interface Preferences {
  showHintBar: boolean;
  corrections: string;
}

export default async function Command() {
  await closeMainWindow();
  const { showHintBar, corrections } = getPreferenceValues<Preferences>();
  await inspect(showHintBar ?? true, corrections ?? "smart");
}
