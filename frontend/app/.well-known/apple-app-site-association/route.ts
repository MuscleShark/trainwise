// Lets iOS open ironsage.app/p/<code> (a shared template) in the IronSage app when it is
// installed (the app's Associated Domains: applinks:ironsage.app). Apple fetches this
// file from the domain's root, without a redirect; www.ironsage.app redirects here, so
// only ironsage.app links open the app.
const APP_ID = "CY5V574249.app.ironsage.IronSage";

export const dynamic = "force-static";

export function GET() {
  return Response.json({
    applinks: {
      details: [{ appIDs: [APP_ID], components: [{ "/": "/p/*", comment: "A shared template" }] }],
    },
  });
}
