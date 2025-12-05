import { NavLink } from "react-router";

const Header = () => {
  return (
    <header className="container py-6">
      <div className="flex items-center justify-between">
        <h1 className="font-bold text-2xl p-2 bg-neutral-800">Tenebris</h1>
        <nav className="space-x-2">
          <NavLink to="/" end>
            Dashboard
          </NavLink>
          <NavLink to="/profiles" end>
            Profiles
          </NavLink>
        </nav>
        <div></div>
      </div>
    </header>
  );
};

export default Header;
