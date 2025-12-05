import { Route, Routes } from "react-router";
import { MainLayout } from "@/widgets";
import { Profiles } from "@/pages";

const App = () => {
  return (
    <main>
      <Routes>
        <Route element={<MainLayout />}>
          {/* <Route index element={<Dashboard />} /> */}
          <Route index element={<Profiles />} />
        </Route>

        {/* <Route element={<AuthLayout />}>
          <Route path="login" element={<Login />} />
        </Route> */}
      </Routes>
    </main>
  );
};

export default App;
